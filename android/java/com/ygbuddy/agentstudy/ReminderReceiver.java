package com.ygbuddy.agentstudy;

import android.app.Notification;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;

public class ReminderReceiver extends BroadcastReceiver {

    @Override
    public void onReceive(Context c, Intent intent) {
        NotificationManager nm = (NotificationManager) c.getSystemService(Context.NOTIFICATION_SERVICE);
        if (nm == null) return;

        Intent open = new Intent(c, MainActivity.class);
        open.setFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TOP);
        PendingIntent pi = PendingIntent.getActivity(c, 0, open,
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);

        Notification n = new Notification.Builder(c, MainActivity.CH_ID)
                .setSmallIcon(android.R.drawable.checkbox_on_background)
                .setContentTitle("今天的主任务还没打卡")
                .setContentText("打开看一眼：四段打卡 + 3 道题")
                .setAutoCancel(true)
                .setContentIntent(pi)
                .build();
        try {
            nm.notify(1001, n);
        } catch (Throwable ignored) {
        }
    }
}
