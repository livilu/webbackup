
cd /var/www

git clone https://github.com/helldweller/webbackup

crontab <<EOF
MAILTO=my@ema.il
00 00 * * 7 /var/www/webbackup/webbackup.sh > /dev/null
EOF