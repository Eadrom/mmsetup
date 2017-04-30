# Mattermost Setup Script

### Synopsis
This script will take a clean Ubuntu 14.04 server on Digital Ocean and set it up to be
used as a Mattermost server.  It also takes care of securing the server.

### Motivation
I wanted an easy way to setup a Mattermost server that would take care of the little things like securing SSH and getting an SSL certificate setup.  I didn't want to have to copy and paste a bunch of stuff and take 20 minutes trying to figure out why Nginx isn't starting to discover I'd forgotten to type a semi-colon.  I also didn't want to have to go through all that again just to set up a test server to try something or setup a secondary server to fail over to temporarily to perform maintenance on the primary server.

### Usage

* Open the new droplet page on Digital Ocean.
* Select the Ubuntu 14.04 distribution.
* Choose a size applicable for your needs.  For a small team, a $10/month droplet will probably be fine.  For larger teams, a $20/month or $40/month droplet will provide the needed CPU and RAM.
* Pick a region applicable for your needs.
* Check the "User Data" box.  A textbox area will open up.
* Copy the contents of mmsetup.sh into the textbox.
* Change any configuration options you would like.  There are several values that you will want to change at minimum.  Those are at the top of the configuration section.
* Pick an SSH key to use.  If you don't pick a key to use, you will not be able to SSH to the server.
* Choose a hostname for your droplet.
* Click the create button!

Some items to note:
* Be sure to use valid values in your configuration.  Invalid settings can cause cause Mattermost to panic and crash.
* If you elect to request Let's Encrypt certificates during setup, you will need the DNS A record created and propagated before the script attempts to request the certificates from Let's Encrypt, otherwise the request will fail.
* There are two scripts in the admin user's in ~/bin/ that will either setup self-signed certificates or will request certificates from Let's Encrypt.  Be sure to restart Nginx after installing certificates.

### Backing Up - WIP

If you want to backup the server or sync the data to a secondary server, the below is what you'll need to copy over.
* PostgreSQL database
* Mattermost's config.json file, probably located in /home/mattermost/config/
* Let's Encrypt certificates, probably located in /etc/letsencrypt/
* DH group, probably located in /etc/ssl/private/
* If you are not using Amazon S3 to store Mattermost data, then you'll need to also copy those files over, probably located in /home/mattermost/data/ or /mattermost/data/

### Contributors

Please open an issue or submit a pull request.

### License

GPL v2.  See LICENSE for more information.
