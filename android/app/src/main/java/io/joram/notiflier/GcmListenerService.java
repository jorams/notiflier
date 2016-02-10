package io.joram.notiflier;

import android.app.NotificationManager;
import android.content.Context;
import android.media.RingtoneManager;
import android.net.Uri;
import android.os.Bundle;
import android.support.v4.app.NotificationCompat;

import java.util.Random;

public class GcmListenerService extends com.google.android.gms.gcm.GcmListenerService {
    @Override
    public void onMessageReceived(String from, Bundle data) {
        // The "notification" part of the GCM message doesn't actually trigger a notification if
        // the app is in the foreground, so we have to show one ourselves.

        String title = data.getString("title", "");
        String body = data.getString("body", "");
        // The "important" property is, for some reason, not a boolean here.
        String important = data.getString("important", "false");

        Uri defaultSoundUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION);
        NotificationCompat.Builder notificationBuilder = new NotificationCompat.Builder(this)
                .setSmallIcon(R.drawable.icon)
                .setContentTitle(title)
                .setContentText(body)
                .setAutoCancel(true)
                .setSound(important.equals("true") ? defaultSoundUri : null);

        NotificationManager notificationManager =
                (NotificationManager) getSystemService(Context.NOTIFICATION_SERVICE);

        // KLUDGE: Randomize the notification id to get rid of merging notifications. Not
        // guaranteed to work of course.
        notificationManager.notify(new Random().nextInt(), notificationBuilder.build());
    }
}
