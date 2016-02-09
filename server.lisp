(defpackage :notiflier
  (:use :cl :hunchentoot :alexandria)
  (:import-from :lparallel
                #:*kernel*
                #:make-kernel
                #:end-kernel
                #:make-channel
                #:submit-task)
  (:import-from :st-json
                #:write-json-to-string
                #:jso)
  (:import-from :vom)
  (:export #:make-notiflier
           #:add-token
           #:remove-token
           #:add-receiver
           #:remove-receiver))
(in-package :notiflier)

;;; Models --------------------------------------------------------------------

(deftype receiver-type ()
  '(member :gcm))

(defun make-receiver (name type data)
  (list :name name :type type :data data))

(defun receiver-type (receiver) (getf receiver :type))
(defun receiver-name (receiver) (getf receiver :name))
(defun receiver-data (receiver indicator)
  (getf (getf receiver :data) indicator))
(defun (setf receiver-data) (value receiver indicator)
  (setf (getf (getf receiver :data) indicator) value))

(defun make-message (title body important)
  (list :title title :body body :important-p important))

(defun message-title (message) (getf message :title))
(defun message-body (message) (getf message :body))
(defun message-important-p (message) (getf message :important-p))

;;; The acceptor carries all state --------------------------------------------

(defclass notiflier-acceptor (acceptor)
  ((receivers-file :initarg :receivers-file :reader receivers-file)
   (%receivers                              :accessor %receivers)
   (tokens-file    :initarg :tokens-file    :reader tokens-file)
   (%tokens                                 :accessor %tokens)
   (gcm-api-key    :initarg :gcm-api-key    :reader gcm-api-key)
   (workers        :initarg :workers        :reader workers)
   ;; Background workers
   (kernel         :initform nil            :accessor kernel)
   (channel        :initform nil            :accessor channel)))

;;; Maintaining receivers -----------------------------------------------------

(defun save-receivers (acceptor)
  (with-open-file (stream (receivers-file acceptor)
                          :direction :output
                          :if-exists :supersede)
    (prin1 (hash-table-alist (%receivers acceptor))
           stream)))

(defun load-receivers (acceptor)
  (with-open-file (stream (receivers-file acceptor)
                          :direction :input
                          :if-does-not-exist nil)
    (setf (%receivers acceptor)
          (alist-hash-table (and stream (read stream nil nil))
                            :test #'equal))))

(defun add-receiver (name type &optional (acceptor *acceptor*))
  (check-type name string)
  (check-type type receiver-type)
  (prog1 name
    (setf (gethash name (%receivers acceptor))
          (make-receiver name type nil))
    (save-receivers acceptor)))

(defun remove-receiver (name &optional (acceptor *acceptor*))
  (check-type name string)
  (remhash name (%receivers acceptor))
  (save-receivers acceptor))

(defun receiver (name &optional (acceptor *acceptor*))
  (check-type name string)
  (gethash name (%receivers acceptor)))

;;; Maintaining tokens --------------------------------------------------------

(defun save-tokens (acceptor)
  (with-open-file (stream (tokens-file acceptor)
                          :direction :output
                          :if-exists :supersede)
    (prin1 (%tokens acceptor) stream)))

(defun load-tokens (acceptor)
  (with-open-file (stream (tokens-file acceptor)
                          :direction :input
                          :if-does-not-exist nil)
    (setf (%tokens acceptor)
          (and stream (read stream nil nil)))))

(defun add-token (token &optional (acceptor *acceptor*))
  (check-type token string)
  (prog1 token
    (pushnew token (%tokens acceptor) :test #'equal)
    (save-tokens acceptor)))

(defun remove-token (token &optional (acceptor *acceptor*))
  (check-type token string)
  (prog1 token
    (removef token (%tokens acceptor) :test #'equal)
    (save-tokens acceptor)))

(defun token (token &optional (acceptor *acceptor*))
  (check-type token string)
  (find token (%tokens acceptor) :test #'equal))

;;; Sending messages ----------------------------------------------------------

;;; GCM

(defparameter +gcm-send-url+ "https://android.googleapis.com/gcm/send")

(defun make-gcm-message (receiver message)
  (if-let ((token (receiver-data receiver :gcm-token)))
    (write-json-to-string
     (jso "to" token
          "data" (jso "title" (or (message-title message)
                                  :null)
                      "body" (or (message-body message)
                                 :null)
                      "important" (if (message-important-p message)
                                      t
                                      :false))
          "notification" (jso "title" (or (message-title message)
                                          :null)
                              "body" (or (message-body message)
                                         :null)
                              "icon" "icon"
                              "sound" (if (message-important-p message)
                                          "default"
                                          :null))))
    (prog1 nil
      (vom:debug "GCM message target not yet registered"))))

(defun gcm-send (target message acceptor)
  (when-let ((headers `(("Authorization" . ,(format nil "key=~A"
                                                    (gcm-api-key acceptor)))))
             (message (make-gcm-message target message)))
    (multiple-value-bind (body status)
        (drakma:http-request +gcm-send-url+
                             :method :POST
                             :content-type "application/json"
                             :additional-headers headers
                             :content message)
      (declare (ignore body))
      (unless (= status 200)
        (vom:warn "Failed to send GCM message. http: ~S message: ~S"
                  status
                  message)))))

;;; General

(defun send (receiver message &optional (acceptor *acceptor*))
  (vom:debug "Sending message to ~A: ~S"
             (receiver-name receiver)
             message)
  (ecase (receiver-type receiver)
    (:gcm (submit-task (channel acceptor)
                       'gcm-send
                       receiver
                       message
                       acceptor))))

(defun broadcast (message &optional (acceptor *acceptor*))
  (vom:debug "Broadcasting message: ~S" message)
  (loop for receiver being the hash-values in (%receivers acceptor)
        do (send receiver message)))

;;; Request handling ----------------------------------------------------------

;;; Utilities

(defun respond (http-code body)
  (prog1 body
    (setf (return-code*) http-code)))

(defun invalid (&optional (what "request"))
  (respond 400 (format nil "Invalid ~A." what)))

(defmacro done (&body body)
  `(prog1 (respond 200 "Done.")
     ,@body))

;;; Handlers

(defun handle-set-gcm-token (&optional (acceptor *acceptor*))
  "POST /gcm-token

Parameters:
- receiver. Required. Name of the receiver who's token to set.
- gcm-token. Required. The new GCM token."
  (if-let ((receiver (receiver (post-parameter "receiver") acceptor))
           (gcm-token (post-parameter "gcm-token")))
    (if (not (eq :gcm (receiver-type receiver)))
        (invalid)
        (done
          (vom:debug "Setting GCM token for ~S to ~S"
                     (receiver-name receiver)
                     gcm-token)
          (setf (receiver-data receiver :gcm-token)
                gcm-token)
          (save-receivers acceptor)))
    (invalid)))

(defun handle-send (&optional (acceptor *acceptor*))
  "POST /send.

Parameters:
- title. Required. The title of the message.
- message. Optional. Message body
- to. Optional. Name of the message's receiver. If not provided, the message
  will be broadcast.
- important. Optional. Provide if the message is important.
"
  (if (null (post-parameter "title"))
      (invalid)
      (let ((message (make-message (post-parameter "title")
                                   (post-parameter "message")
                                   (post-parameter "important"))))
        (if (post-parameter "to")
            (if-let ((receiver (receiver (post-parameter "to"))))
              (done (send receiver message acceptor))
              (invalid "target"))
            (done (broadcast message acceptor))))))

(defun handle-add-receiver (&optional (acceptor *acceptor*))
  "POST /receivers

Parameters:
- name. Required. The name of the new receiver.
- type. Required. The type of the new receiver."
  (if-let ((name (post-parameter "name"))
           (type (post-parameter "type")))
    (cond ((string-equal type "gcm")
           (vom:info "Adding receiver: ~S" name)
           (add-receiver name :gcm acceptor)
           (respond 200 "Receiver added/updated."))
          (t (invalid "receiver type")))
    (invalid)))

(defun handle-add-token (&optional (acceptor *acceptor*))
  "POST /tokens

Parameters:
- new-token. Required. The new token to add."
  (if-let ((new-token (post-parameter "new-token")))
    (done
      (vom:info "Adding token: ~S" new-token)
      (add-token new-token acceptor))
    (invalid)))

;;; Dispatch

(defmethod acceptor-dispatch-request ((acceptor notiflier-acceptor) request)
  (if (and (eq (request-method*) :post)
           (and (post-parameter "token")
                (token (post-parameter "token"))))
      (cond
        ((string= (script-name*) "/gcm-token")
         (handle-set-gcm-token))
        ((string= (script-name*) "/send")
         (handle-send))
        ((string= (script-name*) "/receivers")
         (handle-add-receiver))
        ((string= (script-name*) "/tokens")
         (handle-add-token))
        (t (respond 404 "Not found.")))
      (respond 403 "Nice try.")))

;;; Background workers --------------------------------------------------------
;;; Messages are sent by workers in dedicated worker threads. The threading pool
;;; is started and stopped together with the acceptor.

(defmethod start ((acceptor notiflier-acceptor))
  (let ((*kernel* (make-kernel (workers acceptor))))
    (setf (kernel acceptor) *kernel*)
    (setf (channel acceptor) (make-channel)))
  (when (next-method-p)
    (call-next-method)))

(defmethod stop ((acceptor notiflier-acceptor) &key &allow-other-keys)
  (when-let ((*kernel (kernel acceptor)))
    (end-kernel))
  (when (next-method-p)
    (call-next-method)))

;;; New math ------------------------------------------------------------------

(defun make-notiflier (&key tokens-file receivers-file gcm-api-key (workers 2)
                         (port 5000))
  (assert (or (stringp tokens-file) (pathnamep tokens-file)))
  (assert (or (stringp receivers-file) (pathnamep receivers-file)))
  (ensure-directories-exist tokens-file)
  (ensure-directories-exist receivers-file)
  (let ((notiflier (make-instance 'notiflier-acceptor
                                  :tokens-file tokens-file
                                  :receivers-file receivers-file
                                  :gcm-api-key gcm-api-key
                                  :workers workers
                                  :port port)))
    (prog1 notiflier
      (load-tokens notiflier)
      (load-receivers notiflier))))
