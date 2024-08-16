# We should check for the features needed to run the script in this.
# If anything important is missing, exit without proceeding.

REQUIRED_INIT="systemd";
RUNNING_INIT=$(ps --no-headers -o comm 1);
if [[ "$RUNNING_INIT" != "$REQUIRED_INIT" ]]; then
  echo "system is NOT running systemd, exiting!!!";
  exit;
else
  echo "system is running systemd.";
fi