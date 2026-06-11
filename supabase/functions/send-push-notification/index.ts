// =========================================================================
// Supabase Edge Function: send-push-notification
// تُرسل إشعار FCM لهاتف الموظف عند استقبال طلب POST
// يُستدعى من Database Webhook عند إدراج صف في جدول notifications
// =========================================================================

import { serve } from 'https://deno.land/std@0.177.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const FCM_SERVER_KEY = Deno.env.get('FCM_SERVER_KEY')!;

serve(async (req: Request) => {
  try {
    // Only accept POST requests
    if (req.method !== 'POST') {
      return new Response('Method not allowed', { status: 405 });
    }

    const body = await req.json();
    
    // Supabase Database Webhook sends the new record in body.record
    const record = body.record;
    if (!record || !record.employee_id) {
      return new Response('Invalid payload', { status: 400 });
    }

    const { employee_id, title, body: notifBody } = record;

    // Create admin client to bypass RLS and fetch FCM tokens
    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

    // Fetch all FCM tokens for this employee (they might have multiple devices)
    const { data: tokens, error: tokenError } = await supabase
      .from('fcm_tokens')
      .select('token, device_platform')
      .eq('employee_id', employee_id);

    if (tokenError) {
      console.error('Error fetching FCM tokens:', tokenError);
      return new Response(JSON.stringify({ error: tokenError.message }), { status: 500 });
    }

    if (!tokens || tokens.length === 0) {
      console.log(`No FCM tokens found for employee: ${employee_id}`);
      return new Response(JSON.stringify({ message: 'No tokens found' }), { status: 200 });
    }

    // Send FCM notification to each token
    const results = await Promise.allSettled(
      tokens.map(async ({ token }) => {
        const fcmPayload = {
          to: token,
          notification: {
            title: title || 'تنبيه من نظام HR Pro 🔔',
            body: notifBody || '',
            sound: 'special_chime',   // يجب أن يكون في res/raw للأندرويد
            android_channel_id: 'hr_pro_notifications_channel_v3',
          },
          android: {
            priority: 'high',
            notification: {
              channel_id: 'hr_pro_notifications_channel_v3',
              sound: 'special_chime',
              default_vibrate_timings: true,
              notification_priority: 'PRIORITY_MAX',
              visibility: 'PUBLIC',
            },
          },
          apns: {
            payload: {
              aps: {
                sound: 'special_chime.caf',
                badge: 1,
                'content-available': 1,
              },
            },
          },
          data: {
            type: record.type || 'system',
            employee_id: employee_id,
            notification_id: record.id || '',
          },
        };

        const response = await fetch('https://fcm.googleapis.com/fcm/send', {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'Authorization': `key=${FCM_SERVER_KEY}`,
          },
          body: JSON.stringify(fcmPayload),
        });

        const result = await response.json();
        console.log(`FCM result for token ${token.substring(0, 20)}...:`, JSON.stringify(result));
        return result;
      })
    );

    const successful = results.filter(r => r.status === 'fulfilled').length;
    const failed = results.filter(r => r.status === 'rejected').length;

    return new Response(
      JSON.stringify({
        message: `تم إرسال الإشعار: ${successful} نجح، ${failed} فشل`,
        successful,
        failed,
      }),
      {
        status: 200,
        headers: { 'Content-Type': 'application/json' },
      }
    );
  } catch (error) {
    console.error('Edge Function error:', error);
    return new Response(
      JSON.stringify({ error: String(error) }),
      { status: 500, headers: { 'Content-Type': 'application/json' } }
    );
  }
});
