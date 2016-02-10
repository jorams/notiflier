package io.joram.notiflier;

import android.app.IntentService;
import android.content.Intent;
import android.content.SharedPreferences;
import android.preference.PreferenceManager;
import android.support.v4.content.LocalBroadcastManager;

import com.google.android.gms.gcm.GoogleCloudMessaging;
import com.google.android.gms.iid.InstanceID;

import java.io.BufferedInputStream;
import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStreamReader;
import java.net.HttpURLConnection;
import java.net.URL;
import java.net.URLEncoder;

public class RegistrationIntentService extends IntentService {
    public RegistrationIntentService() {
        super("RegistrationIntentService");
    }

    @Override
    protected void onHandleIntent(Intent intent) {
        SharedPreferences preferences = PreferenceManager.getDefaultSharedPreferences(this);
        String error = null;

        try {
            InstanceID instanceID = InstanceID.getInstance(this);
            String instanceToken = instanceID.getToken(
                    getString(R.string.gcm_defaultSenderId),
                    GoogleCloudMessaging.INSTANCE_ID_SCOPE,
                    null
            );

            String url = preferences.getString(Constants.SERVER_URL, null);
            String token = preferences.getString(Constants.TOKEN, null);
            String name = preferences.getString(Constants.NAME, null);

            if (url == null || token == null || name == null) {
                throw new Exception("Invalid input");
            }

            sendInstanceToken(url, token, name, instanceToken);

            SharedPreferences.Editor editor = preferences.edit();
            editor.putString(
                    Constants.REGISTRATION_STATUS,
                    Constants.RegistrationStatus.COMPLETE.toString()
            );
            editor.apply();
        } catch (Exception e) {
            error = e.getMessage();

            SharedPreferences.Editor editor = preferences.edit();
            editor.putString(
                    Constants.REGISTRATION_STATUS,
                    Constants.RegistrationStatus.FAILED.toString()
            );
            editor.apply();
        }

        Intent registrationComplete = new Intent(Constants.REGISTRATION_STATUS);
        if (error != null) {
            registrationComplete.putExtra(Constants.ERROR_MESSAGE, error);
        }
        LocalBroadcastManager.getInstance(this).sendBroadcast(registrationComplete);
    }

    private void sendInstanceToken(String url, String token, String name, String instanceToken)
            throws Exception {

        HttpURLConnection connection = null;

        try {
            URL registrationURL = new URL(url + "/gcm-token");
            connection = (HttpURLConnection) registrationURL.openConnection();

            connection.setRequestMethod("POST");
            connection.setRequestProperty("Content-Type", "application/x-www-form-urlencoded");

            String query
                    = "token=" + URLEncoder.encode(token, "UTF-8")
                    + "&receiver=" + URLEncoder.encode(name, "UTF-8")
                    + "&gcm-token=" + URLEncoder.encode(instanceToken, "UTF-8");

            connection.setDoOutput(true);
            connection.getOutputStream().write(query.getBytes("UTF-8"));

            BufferedInputStream inputStream = new BufferedInputStream(connection.getInputStream());
            BufferedReader reader = new BufferedReader(new InputStreamReader(inputStream));

            int status = connection.getResponseCode();
            String response;

            StringBuilder sb = new StringBuilder();
            String line;
            while ((line = reader.readLine()) != null) {
                sb.append(line);
            }

            response = sb.toString();

            if (status != 200) {
                throw new Exception(response);
            }
        } catch (IOException e) {
            e.printStackTrace();
            throw e;
        } finally {
            if (connection != null) {
                connection.disconnect();
            }
        }
    }
}
