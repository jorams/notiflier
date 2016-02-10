package io.joram.notiflier;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.content.SharedPreferences;
import android.preference.PreferenceManager;
import android.support.v4.content.LocalBroadcastManager;
import android.support.v7.app.AppCompatActivity;
import android.os.Bundle;
import android.view.View;
import android.widget.EditText;
import android.widget.TextView;
import android.widget.Toast;

public class MainActivity extends AppCompatActivity {

    private BroadcastReceiver _broadcastReceiver;

    private EditText _inputServer;
    private EditText _inputToken;
    private EditText _inputName;
    private TextView _txtNotice;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_main);

        final SharedPreferences preferences = PreferenceManager.getDefaultSharedPreferences(this);

        _inputServer = (EditText) findViewById(R.id.input_server_url);
        _inputToken = (EditText) findViewById(R.id.input_token);
        _inputName = (EditText) findViewById(R.id.input_name);
        _txtNotice = (TextView) findViewById(R.id.txt_notice);

        _inputServer.setText(preferences.getString(Constants.SERVER_URL, ""));
        _inputToken.setText(preferences.getString(Constants.TOKEN, ""));
        _inputName.setText(preferences.getString(Constants.NAME, ""));

        updateNotice();

        // Set up registration
        _broadcastReceiver = new BroadcastReceiver() {
            @Override
            public void onReceive(Context context, Intent intent) {
                updateNotice();

                String error;
                if ((error = intent.getStringExtra(Constants.ERROR_MESSAGE)) != null) {
                    Toast.makeText(
                            MainActivity.this,
                            "Error: " + error,
                            Toast.LENGTH_SHORT
                    ).show();
                }
            }
        };
    }

    private void updateNotice() {
        SharedPreferences preferences = PreferenceManager.getDefaultSharedPreferences(this);

        String statusName = preferences.getString(Constants.REGISTRATION_STATUS, null);
        Constants.RegistrationStatus status;

        if (statusName == null) {
            status = Constants.RegistrationStatus.NONE;
        } else {
            status = Constants.RegistrationStatus.valueOf(statusName);
        }

        if (status == Constants.RegistrationStatus.COMPLETE) {
            _txtNotice.setText(R.string.registration_complete);
        } else if (status == Constants.RegistrationStatus.FAILED) {
            _txtNotice.setText(R.string.registration_failed);
        } else if (status == Constants.RegistrationStatus.STARTED) {
            _txtNotice.setText(R.string.registration_started);
        } else {
            _txtNotice.setText(R.string.awaiting_registration);
        }
    }

    public void saveButtonClicked(View view) {
        if (view.getId() != R.id.btn_save) {
            return;
        }

        final String server = _inputServer.getText().toString();
        final String token = _inputToken.getText().toString();
        final String name = _inputName.getText().toString();

        SharedPreferences preferences = PreferenceManager.getDefaultSharedPreferences(this);
        SharedPreferences.Editor editor = preferences.edit();

        editor.putString(Constants.SERVER_URL, server);
        editor.putString(Constants.TOKEN, token);
        editor.putString(Constants.NAME, name);

        editor.putString(
                Constants.REGISTRATION_STATUS,
                Constants.RegistrationStatus.STARTED.toString()
        );

        editor.apply();

        updateNotice();

        Intent intent = new Intent(this, RegistrationIntentService.class);
        startService(intent);
    }

    @Override
    protected void onResume() {
        super.onResume();
        LocalBroadcastManager.getInstance(this).registerReceiver(
                _broadcastReceiver,
                new IntentFilter(Constants.REGISTRATION_STATUS)
        );
    }

    @Override
    protected void onPause() {
        LocalBroadcastManager.getInstance(this).unregisterReceiver(_broadcastReceiver);
        super.onPause();
    }
}
