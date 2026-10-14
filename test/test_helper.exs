# The fake ingestor in these tests counts every request; the settings poll
# is exercised on its own in remote_settings_test.exs.
Application.put_env(:errorgap, :remote_settings, false)

ExUnit.start()
