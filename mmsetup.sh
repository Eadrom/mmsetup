#!/usr/bin/env bash

# Issues tracked at:
# http://gitlab.1geek4solutions.com/eadrom/mmsetup/issues

# *************************
# * Configuration Options *
# *************************
# Critical Configuration Options
# Administrator's email address
# >>>MUST BE CHANGED<<<
admin_email="name@example.com"
# Sub-domain for server [>mattermost<.example.com]
# >>>MUST BE CHANGED<<<
# Needs to match DNS
mm_sub_domain="mattermost"
# Base-domain for server [mattermost.>example.com<]
# >>>MUST BE CHANGED<<<
# Needs to match DNS
mm_base_domain="example.com"

# General Server Options
# Server administrator's username
admin_user="mmadmin"
# Full path to administrator's public ssh key
admin_ssh_pubkey_path="/root/.ssh/authorized_keys"
# Administrator SSH access group
admin_ssh_group="mmadminssh"
# Size of swap to provision in *megabytes*
swap_size="1024"
# Name of PostgreSQL database to be used by Mattermost server
mm_psql_db="mattermost"
# Username for Mattermost server to access PostreSQL database
mm_psql_user="mmuser"
# Flag (yes or no) to determine if script requests Let's Encrypt SSL certs
le_cloudinit_flag="no"  # "yes" or "no"
# Diffie-Hellman strength in bits (2048= ~1min, 4096= ~1hour)
dh_newgroup_bits="2048"

# Mattermost Storage Configuration Options
# File driver ('local' or 'amazons3')
mm_config_file_driver="local"
# Local storage directory; escape all forward slashes here
mm_config_file_localdir="\/mattermost\/data\/"
# If using S3, this is the region such as us-east-1 or us-west-2
mm_config_s3_region=""
# Name of bucket to be used for file storage
mm_config_s3_bucket=""
# Key ID for S3 IAM user
mm_config_s3_keyid=""
# Access Key for S3 IAM user
mm_config_s3_accesskey=""

# Team Configuration Options
# Site name for Mattermost server, primarily for a bit of branding
mm_config_site_name="Mattermost"
# Max users per team
mm_config_max_team_users="50"
# Can users sign up to the server without an invite?
mm_config_open_signup="false"

# Mattermost Email Configuration Options (Sparkpost defaults noted)
# SMTP Username (SMTP_Injection)
mm_config_smtp_username=""
# SMTP Password (Provided by Sparkpost)
mm_config_smtp_password=""
# SMTP Server (smtp.sparkpostmail.com)
mm_config_smtp_server=""
# SMTP Port (587)
mm_config_smtp_port=""
# SMTP Security (STARTTLS)
mm_config_smtp_security=""
# Email Subject Line
mm_config_email_subject=""
# Mattermost Feedback Contact Email
mm_config_feedback_email=""
# Enable Email Notifications from Mattermost Server (true/false)
mm_config_send_notifications="false"
# Require new users to verify their email address (true/false)
mm_config_verify_email="false"
# Mattermost Support Email
mm_config_support_email="feedback@mattermost.com"
# Permit signing in using username flag
mm_config_signin_username="false"
# Permit signing in using email flag
mm_config_signin_email="true"
# Enable registering an account using email flag
mm_config_register_email="true"
# *************************

# Bring packages to current
apt-get update
apt-get dist-upgrade -y

# Setup admin user
useradd -m -U -s /bin/bash -G sudo $admin_user
mkdir -vp /home/$admin_user/.ssh
cat $admin_ssh_pubkey_path >> /home/$admin_user/.ssh/authorized_keys
chown -R $admin_user:$admin_user /home/$admin_user/.ssh
rm $admin_ssh_pubkey_path
# Create a random password for the new user, set it as the password,
#     then require the password to be changed at login
adminpassword=$(< /dev/urandom tr -dc A-Za-z0-9 | head -c${1:-32};echo;)
echo "$admin_user:$adminpassword" | chpasswd

# Add an ssh users group for additional hardening in sshd_config
groupadd $admin_ssh_group
gpasswd -a $admin_user $admin_ssh_group

# Configure UFW
ufw default deny incoming
ufw default allow outgoing
ufw allow 22
ufw allow 80
ufw allow 443
ufw enable

# Setup SWAP
if [ $swap_size -gt 0 ] ; then
    fallocate -l "$swap_size"M /swapfile
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    echo "/swapfile none swap sw 0 0" >> /etc/fstab
fi

# Configure SSH
# Change server key to 4096
sed -i 's/^ServerKeyBits .*/ServerKeyBits 4096/' /etc/ssh/sshd_config
# Disable root login
sed -i 's/^PermitRootLogin .*/PermitRootLogin no/' /etc/ssh/sshd_config
# Turn off password authentication
sed -i 's/^#PasswordAuthentication .*/PasswordAuthentication no/' /etc/ssh/sshd_config
# Restrict ssh login to only users in the admin_ssh_group group
echo "" >> /etc/ssh/sshd_config
echo "# Only allow users in specific groups to login." >> /etc/ssh/sshd_config
echo "AllowGroups $admin_ssh_group" >> /etc/ssh/sshd_config
# Remove the original ssh server keys and regenerate new stronger 4096 bit keys
rm /etc/ssh/ssh_host_*
dpkg-reconfigure openssh-server

# PostgreSQL Setup
# Install PostgreSQL
apt-get install -y postgresql postgresql-contrib
# Create the Mattermost database
su - postgres -c "psql -c \"CREATE DATABASE $mm_psql_db;\""
# Create the Mattermost database user
# Can change this later with "ALTER USER mmuser WITH PASSWORD '$psqlpassword';" in psql shell
psqlpassword=$(< /dev/urandom tr -dc A-Za-z0-9 | head -c${1:-32};echo;)
su - postgres -c "psql -c \"CREATE USER $mm_psql_user WITH PASSWORD '$psqlpassword';\""
# Grant user access to Mattermost database
su - postgres -c "psql -c \"GRANT ALL PRIVILEGES ON DATABASE $mm_psql_db to $mm_psql_user;\""
# Reload the PostgreSQL database
service postgresql reload

# Mattermost Setup
# Create a mattermost user
useradd -m -U -s /bin/bash mattermost
# Download Mattermost server binary release
# Due to upstream changes, no longer able to download binary releases from GitHub
wget -P /tmp/ https://releases.mattermost.com/3.1.0/mattermost-team-3.1.0-linux-amd64.tar.gz
# Extract server files to mattermost user dir
tar xzvf /tmp/mattermost-team-3.1.0-linux-amd64.tar.gz -C /home/mattermost --strip-components=1
# Correct permissions on server files
chown -R mattermost:mattermost /home/mattermost
# Storage directory for files and images
mkdir -p /mattermost/data
chown -R mattermost:mattermost /mattermost
# Configure Mattermost Server settings
# Install jq for working with the Mattermost JSON config file.
#apt-get install -y jq
# Change database backend to use PostgreSQL
#jq '.SqlSettings.DriverName="postgres"' /home/mattermost/config/config.json > /tmp/tmp.mm.json && mv /tmp/tmp.mm.json /home/mattermost/config/config.json
sed -i 's/"DriverName": "mysql"/"DriverName": "postgres"/' /home/mattermost/config/config.json
#jq '.SqlSettings.DataSource="postgres://'"$mm_psql_user"':'"$psqlpassword"'@127.0.0.1:5432/'"$mm_psql_db"'?sslmode=disable&connect_timeout=10"' /home/mattermost/config/config.json > /tmp/tmp.mm.json && mv /tmp/tmp.mm.json /home/mattermost/config/config.json
sed -i 's#^\(\s*"DataSource"\s*:\s*\)".*"\s*\(,\?\)$#\1"postgres://'"$mm_psql_user"':'"$psqlpassword"'@127.0.0.1:5432/'"$mm_psql_db"'\?sslmode=disable\&connect_timeout=10"\2#' /home/mattermost/config/config.json  # Many thanks to Ryan Moeller <ryan@freqlabs.com> for the path out of REGEX hell here

# Mattermost Email Settings - WIP
#jq '.SupportSettings.SupportEmail="'"$mm_config_support_email"'"' /home/mattermost/config/config.json > /tmp/tmp.mm.json && mv /tmp/tmp.mm.json /home/mattermost/config/config.json
sed -i 's/"SupportEmail": "feedback@mattermost.com"/"SupportEmail": "'"$mm_config_support_email"'"/' /home/mattermost/config/config.json
#jq '.EmailSettings.SMTPServer="'"$mm_config_smtp_server"'"' /home/mattermost/config/config.json > /tmp/tmp.mm.json && mv /tmp/tmp.mm.json /home/mattermost/config/config.json
sed -i 's/"SMTPServer": ""/"SMTPServer": "'"$mm_config_smtp_server"'"/' /home/mattermost/config/config.json
#jq '.EmailSettings.SMTPPort="'"$mm_config_smtp_port"'"' /home/mattermost/config/config.json > /tmp/tmp.mm.json && mv /tmp/tmp.mm.json /home/mattermost/config/config.json
sed -i 's/"SMTPPort": ""/"SMTPPort": "'"$mm_config_smtp_port"'"/' /home/mattermost/config/config.json
#jq '.EmailSettings.ConnectionSecurity="'"$mm_config_smtp_security"'"' /home/mattermost/config/config.json > /tmp/tmp.mm.json && mv /tmp/tmp.mm.json /home/mattermost/config/config.json
sed -i 's/"ConnectionSecurity": ""/"ConnectionSecurity": "'"$mm_config_smtp_security"'"/' /home/mattermost/config/config.json
#jq '.EmailSettings.SMTPUsername="'"$mm_config_smtp_username"'"' /home/mattermost/config/config.json > /tmp/tmp.mm.json && mv /tmp/tmp.mm.json /home/mattermost/config/config.json
sed -i 's/"SMTPUsername": ""/"SMTPUsername": "'"$mm_config_smtp_username"'"/' /home/mattermost/config/config.json
#jq '.EmailSettings.SMTPPassword="'"$mm_config_smtp_password"'"' /home/mattermost/config/config.json > /tmp/tmp.mm.json && mv /tmp/tmp.mm.json /home/mattermost/config/config.json
sed -i 's/"SMTPPassword": ""/"SMTPPassword": "'"$mm_config_smtp_password"'"/' /home/mattermost/config/config.json
#jq '.EmailSettings.FeedbackEmail="'"$mm_config_feedback_email"'"' /home/mattermost/config/config.json > /tmp/tmp.mm.json && mv /tmp/tmp.mm.json /home/mattermost/config/config.json
sed -i 's/"FeedbackEmail": ""/"FeedbackEmail": "'"$mm_config_feedback_email"'"/' /home/mattermost/config/config.json
#jq '.EmailSettings.FeedbackName="'"$mm_config_email_subject"'"' /home/mattermost/config/config.json > /tmp/tmp.mm.json && mv /tmp/tmp.mm.json /home/mattermost/config/config.json
sed -i 's/"FeedbackName": ""/"FeedbackName": "'"$mm_config_email_subject"'"/' /home/mattermost/config/config.json
#jq '.EmailSettings.RequireEmailVerification='"$mm_config_verify_email"'' /home/mattermost/config/config.json > /tmp/tmp.mm.json && mv /tmp/tmp.mm.json /home/mattermost/config/config.json
sed -i 's/"RequireEmailVerification": false/"RequireEmailVerification": '"$mm_config_verify_email"'/' /home/mattermost/config/config.json
#jq '.EmailSettings.SendEmailNotifications='"$mm_config_send_notifications"'' /home/mattermost/config/config.json > /tmp/tmp.mm.json && mv /tmp/tmp.mm.json /home/mattermost/config/config.json
sed -i 's/"SendEmailNotifications": false/"SendEmailNotifications": '"$mm_config_send_notifications"'/' /home/mattermost/config/config.json
#jq '.EmailSettings.EnableSignInWithUsername='"$mm_config_signin_username"'' /home/mattermost/config/config.json > /tmp/tmp.mm.json && mv /tmp/tmp.mm.json /home/mattermost/config/config.json
sed -i 's/"EnableSignInWithUsername": false/"EnableSignInWithUsername": '"$mm_config_signin_username"'/' /home/mattermost/config/config.json
#jq '.EmailSettings.EnableSignInWithEmail='"$mm_config_signin_email"'' /home/mattermost/config/config.json > /tmp/tmp.mm.json && mv /tmp/tmp.mm.json /home/mattermost/config/config.json
sed -i 's/"EnableSignInWithEmail": true/"EnableSignInWithEmail": '"$mm_config_signin_email"'/' /home/mattermost/config/config.json
#jq '.EmailSettings.EnableSignUpWithEmail='"$mm_config_register_email"'' /home/mattermost/config/config.json > /tmp/tmp.mm.json && mv /tmp/tmp.mm.json /home/mattermost/config/config.json
sed -i 's/"EnableSignUpWithEmail": true/"EnableSignUpWithEmail": '"$mm_config_register_email"'/' /home/mattermost/config/config.json

# Mattermost File Settings - WIP
#jq '.FileSettings.DriverName="'"$mm_config_file_driver"'"' /home/mattermost/config/config.json > /tmp/tmp.mm.json && mv /tmp/tmp.mm.json /home/mattermost/config/config.json
sed -i 's/"DriverName": "local"/"DriverName": "'"$mm_config_file_driver"'"/' /home/mattermost/config/config.json
#jq '.FileSettings.Directory="'"$mm_config_file_localdir"'"' /home/mattermost/config/config.json > /tmp/tmp.mm.json && mv /tmp/tmp.mm.json /home/mattermost/config/config.json
sed -i 's/"Directory": ".\/data\/"/"Directory": "'"$mm_config_file_localdir"'"/' /home/mattermost/config/config.json
#jq '.FileSettings.AmazonS3Region="'"$mm_config_s3_region"'"' /home/mattermost/config/config.json > /tmp/tmp.mm.json && mv /tmp/tmp.mm.json /home/mattermost/config/config.json
sed -i 's/"AmazonS3Region": ""/"AmazonS3Region": "'"$mm_config_s3_region"'"/' /home/mattermost/config/config.json
#jq '.FileSettings.AmazonS3Bucket="'"$mm_config_s3_bucket"'"' /home/mattermost/config/config.json > /tmp/tmp.mm.json && mv /tmp/tmp.mm.json /home/mattermost/config/config.json
sed -i 's/"AmazonS3Bucket": ""/"AmazonS3Bucket": "'"$mm_config_s3_bucket"'"/' /home/mattermost/config/config.json
#jq '.FileSettings.AmazonS3AccessKeyId="'"$mm_config_s3_keyid"'"' /home/mattermost/config/config.json > /tmp/tmp.mm.json && mv /tmp/tmp.mm.json /home/mattermost/config/config.json
sed -i 's/"AmazonS3AccessKeyId": ""/"AmazonS3AccessKeyId": "'"$mm_config_s3_keyid"'"/' /home/mattermost/config/config.json
#jq '.FileSettings.AmazonS3SecretAccessKey="'"$mm_config_s3_accesskey"'"' /home/mattermost/config/config.json > /tmp/tmp.mm.json && mv /tmp/tmp.mm.json /home/mattermost/config/config.json
sed -i 's/"AmazonS3SecretAccessKey": ""/"AmazonS3SecretAccessKey": "'"$mm_config_s3_accesskey"'"/' /home/mattermost/config/config.json

# Team Settings - WIP
#jq '.TeamSettings.SiteName="'"$mm_config_site_name"'"' /home/mattermost/config/config.json > /tmp/tmp.mm.json && mv /tmp/tmp.mm.json /home/mattermost/config/config.json
sed -i 's/"SiteName": "Mattermost"/"SiteName": "'"$mm_config_site_name"'"/' /home/mattermost/config/config.json
#jq '.TeamSettings.MaxUsersPerTeam="'"$mm_config_max_team_users"'"' /home/mattermost/config/config.json > /tmp/tmp.mm.json && mv /tmp/tmp.mm.json /home/mattermost/config/config.json
sed -i 's/"MaxUsersPerTeam": 50/"MaxUsersPerTeam": '"$mm_config_max_team_users"'/' /home/mattermost/config/config.json
#jq '.TeamSettings.EnableOpenServer="'"$mm_config_open_signup"'"' /home/mattermost/config/config.json > /tmp/tmp.mm.json && mv /tmp/tmp.mm.json /home/mattermost/config/config.json
sed -i 's/"EnableOpenServer": false/"EnableOpenServer": '"$mm_config_open_signup"'/' /home/mattermost/config/config.json

# Generate new salts
# Default for "AtRestEncryptKey": "7rAh6iwQCkV4cA1Gsg3fgGOXJAQ43QVg"
newsalt=$(< /dev/urandom tr -dc A-Za-z0-9 | head -c${1:-32};echo;)
sed -i 's/"AtRestEncryptKey": "7rAh6iwQCkV4cA1Gsg3fgGOXJAQ43QVg"/"AtRestEncryptKey": "'"$newsalt"'"/' /home/mattermost/config/config.json
# Default for "InviteSalt": "bjlSR4QqkXFBr7TP4oDzlfZmcNuH9YoS"
newsalt=$(< /dev/urandom tr -dc A-Za-z0-9 | head -c${1:-32};echo;)
sed -i 's/"InviteSalt": "bjlSR4QqkXFBr7TP4oDzlfZmcNuH9YoS"/"InviteSalt": "'"$newsalt"'"/' /home/mattermost/config/config.json
# Default for "PasswordResetSalt": "vZ4DcKyVVRlKHHJpexcuXzojkE5PZ5eL"
newsalt=$(< /dev/urandom tr -dc A-Za-z0-9 | head -c${1:-32};echo;)
sed -i 's/"PasswordResetSalt": "vZ4DcKyVVRlKHHJpexcuXzojkE5PZ5eL"/"PasswordResetSalt": "'"$newsalt"'"/' /home/mattermost/config/config.json
# Default for "PublicLinkSalt": "A705AklYF8MFDOfcwh3I488G8vtLlVip"
newsalt=$(< /dev/urandom tr -dc A-Za-z0-9 | head -c${1:-32};echo;)
sed -i 's/"PublicLinkSalt": "A705AklYF8MFDOfcwh3I488G8vtLlVip"/"PublicLinkSalt": "'"$newsalt"'"/' /home/mattermost/config/config.json

# Make sure mattermost user owns config file
chown mattermost:mattermost /home/mattermost/config/config.json

# Setup Upstart daemon config
touch /etc/init/mattermost.conf
echo "start on runlevel [2345]" > /etc/init/mattermost.conf
echo "stop on runlevel [016]" >> /etc/init/mattermost.conf
echo "respawn" >> /etc/init/mattermost.conf
echo "chdir /home/mattermost" >> /etc/init/mattermost.conf
echo "setuid mattermost" >> /etc/init/mattermost.conf
echo "exec bin/platform" >> /etc/init/mattermost.conf

# Install Let's Encrypt's certbot client's dependencies
apt-get install -y git bc
# Download Let's Encrypt certbot client
git clone https://github.com/certbot/certbot /opt/certbot --depth 1
# Setup the Let's Encrypt CLI config
cp /opt/certbot/examples/cli.ini /usr/local/etc/le-config-webroot.ini
sed -i 's/^# email .*/email = '"$admin_email"'/' /usr/local/etc/le-config-webroot.ini
sed -i 's/^# domains = .*/domains = '"$mm_sub_domain"'.'"$mm_base_domain"'/' /usr/local/etc/le-config-webroot.ini
sed -i 's/^# webroot-path .*/webroot-path = \/usr\/share\/nginx\/html/' /usr/local/etc/le-config-webroot.ini
sed -i 's/^# authenticator = w.*/authenticator = webroot/' /usr/local/etc/le-config-webroot.ini

# Install Nginx
apt-get install -y nginx

# Generate a new, more secure DH group
# Takes approx 1 min per `/usr/bin/time -f %E` for a 2048 bit key
openssl dhparam -out /etc/ssl/private/dhparams.pem "$dh_newgroup_bits"
chmod 0600 /etc/ssl/private/dhparams.pem

# Create Mattermost server configuration file
touch /etc/nginx/sites-available/mattermost
echo "server {" >> /etc/nginx/sites-available/mattermost
echo "    listen          80;" >> /etc/nginx/sites-available/mattermost
echo "    server_name     $mm_sub_domain.$mm_base_domain;" >> /etc/nginx/sites-available/mattermost
echo "    return          301 https://\$server_name\$request_uri;" >> /etc/nginx/sites-available/mattermost
echo "}" >> /etc/nginx/sites-available/mattermost
echo "" >> /etc/nginx/sites-available/mattermost
echo "server {" >> /etc/nginx/sites-available/mattermost
echo "    listen          443 ssl;" >> /etc/nginx/sites-available/mattermost
echo "    server_name     $mm_sub_domain.$mm_base_domain;" >> /etc/nginx/sites-available/mattermost
echo "" >> /etc/nginx/sites-available/mattermost
echo "    ssl on;" >> /etc/nginx/sites-available/mattermost
echo "    ssl_certificate /etc/letsencrypt/live/$mm_sub_domain.$mm_base_domain/fullchain.pem;" >> /etc/nginx/sites-available/mattermost
echo "    ssl_certificate_key /etc/letsencrypt/live/$mm_sub_domain.$mm_base_domain/privkey.pem;" >> /etc/nginx/sites-available/mattermost
echo "    ssl_session_timeout 5m;" >> /etc/nginx/sites-available/mattermost
echo "    ssl_protocols TLSv1 TLSv1.1 TLSv1.2;" >> /etc/nginx/sites-available/mattermost
echo "    ssl_ciphers 'ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-AES256-GCM-SHA384:DHE-RSA-AES128-GCM-SHA256:DHE-DSS-AES128-GCM-SHA256:kEDH+AESGCM:ECDHE-RSA-AES128-SHA256:ECDHE-ECDSA-AES128-SHA256:ECDHE-RSA-AES128-SHA:ECDHE-ECDSA-AES128-SHA:ECDHE-RSA-AES256-SHA384:ECDHE-ECDSA-AES256-SHA384:ECDHE-RSA-AES256-SHA:ECDHE-ECDSA-AES256-SHA:DHE-RSA-AES128-SHA256:DHE-RSA-AES128-SHA:DHE-DSS-AES128-SHA256:DHE-RSA-AES256-SHA256:DHE-DSS-AES256-SHA:DHE-RSA-AES256-SHA:AES128-GCM-SHA256:AES256-GCM-SHA384:AES128-SHA256:AES256-SHA256:AES128-SHA:AES256-SHA:AES:CAMELLIA:DES-CBC3-SHA:!aNULL:!eNULL:!EXPORT:!DES:!RC4:!MD5:!PSK:!aECDH:!EDH-DSS-DES-CBC3-SHA:!EDH-RSA-DES-CBC3-SHA:!KRB5-DES-CBC3-SHA';" >> /etc/nginx/sites-available/mattermost
echo "    ssl_prefer_server_ciphers on;" >> /etc/nginx/sites-available/mattermost
echo "    ssl_session_cache shared:SSL:10m;" >> /etc/nginx/sites-available/mattermost
echo "    ssl_dhparam /etc/ssl/private/dhparams.pem;" >> /etc/nginx/sites-available/mattermost
echo "" >> /etc/nginx/sites-available/mattermost
echo "    location '/.well-known/acme-challenge' {" >> /etc/nginx/sites-available/mattermost
echo "        root /usr/share/nginx/html/;" >> /etc/nginx/sites-available/mattermost
echo "        try_files \$uri /\$1;" >> /etc/nginx/sites-available/mattermost
echo "    }" >> /etc/nginx/sites-available/mattermost
echo "" >> /etc/nginx/sites-available/mattermost
echo "    location / {" >> /etc/nginx/sites-available/mattermost
echo "        gzip off;" >> /etc/nginx/sites-available/mattermost
echo "        proxy_set_header X-Forwarded-Ssl on;" >> /etc/nginx/sites-available/mattermost
echo "        client_max_body_size 50M;" >> /etc/nginx/sites-available/mattermost
echo "        proxy_set_header Upgrade \$http_upgrade;" >> /etc/nginx/sites-available/mattermost
echo "        proxy_set_header Connection \"upgrade\";" >> /etc/nginx/sites-available/mattermost
echo "        proxy_set_header Host \$http_host;" >> /etc/nginx/sites-available/mattermost
echo "        proxy_set_header X-Real-IP \$remote_addr;" >> /etc/nginx/sites-available/mattermost
echo "        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;" >> /etc/nginx/sites-available/mattermost
echo "        proxy_set_header X-Forwarded-Proto \$scheme;" >> /etc/nginx/sites-available/mattermost
echo "        proxy_set_header X-Frame-Options SAMEORIGIN;" >> /etc/nginx/sites-available/mattermost
echo "        proxy_pass http://127.0.0.1:8065;" >> /etc/nginx/sites-available/mattermost
echo "    }" >> /etc/nginx/sites-available/mattermost
echo "}" >> /etc/nginx/sites-available/mattermost
# Create a bootstrap configuration file for Let's Encrypt
touch /etc/nginx/sites-available/bootstrap
echo "server {" >> /etc/nginx/sites-available/bootstrap
echo "    root /usr/share/nginx/html;" >> /etc/nginx/sites-available/bootstrap
echo "    index index.html index.htm;" >> /etc/nginx/sites-available/bootstrap
echo "    server_name localhost;" >> /etc/nginx/sites-available/bootstrap
echo "    location '/.well-known/acme-challenge' {" >> /etc/nginx/sites-available/bootstrap
echo "        root /usr/share/nginx/html/;" >> /etc/nginx/sites-available/bootstrap
echo "        try_files \$uri /\$1;" >> /etc/nginx/sites-available/bootstrap
echo "    }" >> /etc/nginx/sites-available/bootstrap
echo "}" >> /etc/nginx/sites-available/bootstrap
# Remove the default site
rm /etc/nginx/sites-enabled/default
# Enable the bootstrap config
ln -s /etc/nginx/sites-available/bootstrap /etc/nginx/sites-enabled/bootstrap

# Request Let's Encrypt cert for the server
# Active certs live in /etc/letsencrypt/live/$mm_sub_domain.$mm_base_domain/
# Set the le_cloudinit_flag variable to "yes" to request certs during cloud-init
if [ "$le_cloudinit_flag" == "yes" ] ; then
    /opt/certbot/certbot-auto certonly -n --agree-tos --config /usr/local/etc/le-config-webroot.ini
    # Disable the bootstrap config
    rm /etc/nginx/sites-enabled/bootstrap
    # Enable the mattermost config
    ln -s /etc/nginx/sites-available/mattermost /etc/nginx/sites-enabled/mattermost
fi

# The above command is going to fail at cloud-init run time if the A record DNS entry has not been created yet
#     Could solve this by creating a floating IP, then attaching the new droplet to that floating IP.  That way
#     the DNS record could already exist...
# Create a script for server admin in case Let's Encrypt certs not requested during cloud-init run
su - $admin_user -c "mkdir /home/$admin_user/bin"
su - $admin_user -c "touch /home/$admin_user/bin/request_le_certs.sh"
echo '#!/usr/bin/env bash' > /home/$admin_user/bin/request_le_certs.sh
echo "sudo /opt/certbot/certbot-auto certonly -n --agree-tos --config /usr/local/etc/le-config-webroot.ini" >> /home/$admin_user/bin/request_le_certs.sh
echo "sudo chmod 0700 /etc/cron.weekly/le-renew.sh" >> /home/$admin_user/bin/request_le_certs.sh
echo "sudo rm /etc/nginx/sites-enabled/bootstrap" >> /home/$admin_user/bin/request_le_certs.sh
echo "sudo ln -s /etc/nginx/sites-available/mattermost /etc/nginx/sites-enabled/mattermost" >> /home/$admin_user/bin/request_le_certs.sh
echo "sudo service nginx restart" >> /home/$admin_user/bin/request_le_certs.sh
chmod 0700 /home/$admin_user/bin/request_le_certs.sh
# Alternate admin command to create self signed certificates
su - $admin_user -c "touch /home/$admin_user/bin/install_self_signed_certs.sh"
echo '#!/usr/bin/env bash' > /home/$admin_user/bin/install_self_signed_certs.sh
echo "sudo mkdir -p /etc/letsencrypt/live/$mm_sub_domain.$mm_base_domain" >> /home/$admin_user/bin/install_self_signed_certs.sh
echo "sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /etc/letsencrypt/live/$mm_sub_domain.$mm_base_domain/privkey.pem -out /etc/letsencrypt/live/$mm_sub_domain.$mm_base_domain/fullchain.pem" >> /home/$admin_user/bin/install_self_signed_certs.sh
echo "sudo rm /etc/nginx/sites-enabled/bootstrap" >> /home/$admin_user/bin/install_self_signed_certs.sh
echo "sudo ln -s /etc/nginx/sites-available/mattermost /etc/nginx/sites-enabled/mattermost" >> /home/$admin_user/bin/install_self_signed_certs.sh
echo "sudo service nginx restart" >> /home/$admin_user/bin/install_self_signed_certs.sh
chmod 0700 /home/$admin_user/bin/install_self_signed_certs.sh

# Create a script in /etc/cron.weekly to attempt cert renewal once a week.
echo '#!/usr/bin/env bash' > /etc/cron.weekly/le-renew.sh
echo "/opt/certbot/certbot-auto certonly -n --agree-tos --config /usr/local/etc/le-config-webroot.ini" >> /etc/cron.weekly/le-renew.sh
# If le_cloudinit_flag is set to "yes", go ahead and turn on the auotmatic renewal cronjob
if [ "$le_cloudinit_flag" == "yes" ] ; then
    chmod 0700 /etc/cron.weekly/le-renew.sh
fi

# Make the admin user change the default password the first time they log in
# We do this now instead of at user creation above so this check is not performed when making ssl scripts
su - $admin_user -c "touch /home/$admin_user/.firstlogin"
echo $adminpassword > /home/$admin_user/.firstlogin
echo '' >> /home/$admin_user/.profile
echo 'if [ -f "$HOME/.firstlogin" ] ; then' >> /home/$admin_user/.profile
echo '    echo "Password is required to be changed."' >> /home/$admin_user/.profile
echo '    echo "Password setup during install for you is:"' >> /home/$admin_user/.profile
echo '    cat $HOME/.firstlogin' >> /home/$admin_user/.profile
echo '    passwd' >> /home/$admin_user/.profile
echo '    mv $HOME/.firstlogin $HOME/.oldlogin' >> /home/$admin_user/.profile
echo 'fi' >> /home/$admin_user/.profile

/sbin/shutdown -r now
