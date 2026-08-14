# Run Liz against your live Supabase project (Chrome).
# The anon key is a client-side key (it ships in the app bundle), so it's safe here.
# NEVER put the service_role key or DB password in this file.

flutter run -d chrome `
  --dart-define=SUPABASE_URL=https://yluabeijvbydxczfxclk.supabase.co `
  --dart-define=SUPABASE_ANON_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InlsdWFiZWlqdmJ5ZHhjemZ4Y2xrIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODYzODY4NTUsImV4cCI6MjEwMTk2Mjg1NX0.zvbMoLLaPxmXxCbtDsTQ8Io3UDy4lq-wA5TQ6g_l-sI `
  --dart-define=FCM_VAPID_KEY=BIitqxiFRR0cEvigb_4tP1W4kmhgCdTgV4mGvNU65dCYeGSre8u7HKfnDz8BS_V9sbI0nKRtidktjklXSR2J5AY
