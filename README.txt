This folder contains files for CEDAPug game server integration. 

A valid API key provided by Luckylock is required for the plugins to be allowed to interact with cedapug.com.

- addons/sourcemod/plugins/optional/l4d2_cedapug_rank.smx: Plugin that sends scores and players data.
- addons/sourcemod/plugins/optional/l4d2_cedapug_sub.smx: Plugin that allows players to ask for a substitute.
- addons/sourcemod/plugins/optional/l4d2_cedapug_detect.smx: Plugin that detects a cedapug game on the first live round.
- addons/sourcemod/plugins/optional/l4d2_cedapug_robocop.smx: Plugin that provides some automatic moderation.
- addons/sourcemod/data/cedapug_settings.txt: Settings file for the CEDAPug API key.

Here are the steps required to setup the integration:

1. Install the System2 v3.3.2 extension (https://github.com/dordnung/System2/releases/tag/v3.3.2).
2. Upload the addons folder.
3. Add the plugins in cfg/sharedplugins.cfg.
4. Set a valid API key and url in addons/sourcemod/data/cedapug_settings.txt.

To get the System2 extension working

apt-get install lib32stdc++6
rm steam/steamapps/commmon/l4d2/bin/libgcc_s.so.1
rm steam/steamapps/common/l4d2/bin/libstdc++.so.6
