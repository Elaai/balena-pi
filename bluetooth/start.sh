#!/usr/bin/env bash

if [[ -z "$BLUETOOTH_DEVICE_NAME" ]]; then
  BLUETOOTH_DEVICE_NAME=$(printf "balenaSound %s" $(hostname | cut -c -4))
fi

# Set the system volume here
SYSTEM_OUTPUT_VOLUME="${SYSTEM_OUTPUT_VOLUME:-75}"
echo $SYSTEM_OUTPUT_VOLUME > /usr/src/system_output_volume
printf "Setting output volume to %s%%\n" "$SYSTEM_OUTPUT_VOLUME"
amixer sset PCM,0 $SYSTEM_OUTPUT_VOLUME% > /dev/null &
amixer sset Digital,0 $SYSTEM_OUTPUT_VOLUME% > /dev/null &

# Set the volume of the connection notification sounds here
CONNECTION_NOTIFY_VOLUME="${CONNECTION_NOTIFY_VOLUME:-75}"
echo $CONNECTION_NOTIFY_VOLUME > /usr/src/connection_notify_volume
printf "Connection notify volume is %s%%\n" "$CONNECTION_NOTIFY_VOLUME"

# Set the discoverable timeout here
dbus-send --system --dest=org.bluez --print-reply /org/bluez/hci0 org.freedesktop.DBus.Properties.Set string:'org.bluez.Adapter1' string:'DiscoverableTimeout' variant:uint32:0 > /dev/null

printf "Restarting bluetooth service\n"
service bluetooth restart > /dev/null
sleep 2

# Redirect stdout to null, because it prints the old BT device name, which
# can be confusing and it also hides those commands from the logs as well.
printf "discoverable on\npairable on\nexit\n" | bluetoothctl > /dev/null

# Start bluetooth and audio agent
/usr/src/bluetooth-agent &

# If multi room is disabled remove audio redirect to fifo pipe
# Also remove if device is from Pi 1 family, since snapcast server is disabled by default
if [[ -n $DISABLE_MULTI_ROOM ]] || [[ $BALENA_DEVICE_TYPE == "raspberry-pi" ]]; then
  rm /root/.asoundrc
fi

sleep 2
rm -rf /var/run/bluealsa/
/usr/bin/bluealsa -i hci0 -p a2dp-sink --a2dp-volume &

hciconfig hci1 down > /dev/null 2>&1 # Disable onboard bluetooth if using a bluetooth dongle (onboard interface gets remapped to hci1) 

if [[ -z "$DISABLE_AUTO_DISCOVERY" ]]; then
  hciconfig hci0 up
fi

hciconfig hci0 name "$BLUETOOTH_DEVICE_NAME"

if ! [ -z "$BLUETOOTH_PIN_CODE" ] && [[ $BLUETOOTH_PIN_CODE -gt 1 ]] && [[ $BLUETOOTH_PIN_CODE -lt 1000000 ]]; then
  hciconfig hci0 sspmode 0  # Legacy pairing (PIN CODE)
  printf "Starting bluetooth agent in Legacy Pairing Mode - PIN CODE is \"%s\"\n" "$BLUETOOTH_PIN_CODE"
else
  hciconfig hci0 sspmode 1  # Secure Simple Pairing
  printf "Starting bluetooth agent in Secure Simple Pairing Mode (SSPM) - No PIN code provided or invalid\n"
fi

# Reconnect if there is a known device
sleep 2
if [ -f "/var/cache/bluetooth/reconnect_device" ]; then
  TRUSTED_MAC_ADDRESS=$(cat /var/cache/bluetooth/reconnect_device)
  printf "Attempting to reconnect to previous bluetooth device: %s\n" "$TRUSTED_MAC_ADDRESS"
  printf "connect %s\nexit\n" "$TRUSTED_MAC_ADDRESS" | bluetoothctl > /dev/null
fi

# Start gpio bluetooth control service
if [[ -z "$DISABLE_BLUETOOTH_CONTROL" ]]; then
  VOLUME_UP_GPIO="${VOLUME_UP_GPIO:-17}"
  echo $VOLUME_UP_GPIO > /usr/src/volume_up_gpio
  printf "Volume up button input is on GPIO$VOLUME_UP_GPIO %s%%\n"

  BLUETOOTH_GPIO="${BLUETOOTH_GPIO:-27}"
  echo $BLUETOOTH_GPIO > /usr/src/bluetooth_gpio
  printf "Bluetooth button input is on GPIO$BLUETOOTH_GPIO %s%%\n"

  VOLUME_DOWN_GPIO="${VOLUME_DOWN_GPIO:-22}"
  echo $VOLUME_DOWN_GPIO > /usr/src/volume_down_gpio
  printf "Volume down button input is on GPIO$VOLUME_DOWN_GPIO %s%%\n"
  
  bash /usr/src/bluetooth-control &
fi

sleep 2
printf "Device is discoverable as \"%s\"\n" "$BLUETOOTH_DEVICE_NAME"
exec /usr/bin/bluealsa-aplay --profile-a2dp 00:00:00:00:00:00
