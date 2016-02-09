(asdf:defsystem :notiflier
  :description "Simple self-hosted push notifications"
  :author "Joram Schrijver <i@joram.io>"
  :license "MIT"
  :depends-on (#:hunchentoot
               #:alexandria
               #:drakma
               #:lparallel
               #:st-json
               #:vom)
  :components ((:file "server")))
