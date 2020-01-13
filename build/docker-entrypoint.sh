#!/bin/bash
# set -euo pipefail # things are crashing, but I want to continue... Seb

if [[ "$1" == apache2* ]] || [ "$1" == php-fpm ]; then
  if [ "$(id -u)" = '0' ]; then
    case "$1" in
      apache2*)
        user="${UID:-www-data}"
        group="${GID:-www-data}"
        ;;
      *) # php-fpm
        user='www-data'
        group='www-data'
        ;;
    esac
  else
    user="$(id -u)"
    group="$(id -g)"
  fi

  # Copy files to the web directory if they don't exist already
  if ! [ -e index.php ]; then
          echo >&2 "OctoberCMS not found in $(pwd) - copying now..."
          if [ "$(ls -A)" ]; then
                  echo >&2 "WARNING: $(pwd) is not empty - press Ctrl+C now if this is an error!"
                  ( set -x; ls -A; sleep 10 )
          fi

          tar --create \
            --file - \
            --one-file-system \
            --directory /usr/src/october \
            --owner "$user" --group "$group" \
            . | tar --extract --file -

          echo >&2 "Complete! OctoberCMS has been successfully copied to $(pwd)"

          echo "user: $user group: $group"
          echo "current directory: $(pwd)"
          chown -R $user:$group . 
  fi

  # if we have a clean repo then install
  if ! [ -d vendor ]; then
    echo "Run composer install on site"
    composer install
  fi

  # Generate random key for laravel if it's not specified
  php artisan key:generate

  # Make sure we have the right permissions
  if [ -f /root/.ssh/id_rsa ]; then
    echo "chmod id_rsa file"
    chmod 0600 /root/.ssh/id_rsa
  fi

  # Add git host keys to known hosts
  IFS=';' read -ra KEY <<< "${GIT_HOSTS:-}"
  for i in "${KEY[@]}"; do
      ssh-keyscan -H $i >> /root/.ssh/known_hosts
  done

  # debugging
  echo "!!!!!!!!!!!!!!!User is:"
  id -u

  # git clone plugins and themes was here

  # chown -R $APACHE_RUN_USER:$APACHE_RUN_GROUP /var/www/html

: ${OCTOBER_DB_DRIVER:='sqlite'}

  # If we don't need a database we can bail here
  if [ "$OCTOBER_DB_DRIVER" == 'none' ] ; then
    echo >&2 'Notice! Database has been disabled.'
    exec "$@"
  fi

  # Set default database port if not already set by environment
  if [ "$OCTOBER_DB_DRIVER" == 'mysql' ] ; then
    : ${OCTOBER_DB_HOST:='mysql'}
    : ${OCTOBER_DB_PORT:=3306}
    : ${OCTOBER_DB_USER:='root'}
  fi

  if [ "$OCTOBER_DB_DRIVER" == 'pgsql' ] ; then
    : ${OCTOBER_DB_HOST:='postgres'}
    : ${OCTOBER_DB_PORT:=5432}
    : ${OCTOBER_DB_USER:='postgres'}
  fi
  
  # Set default database name if not already set by environment
  : ${OCTOBER_DB_NAME:='october_cms'}

  if [ -z "${OCTOBER_DB_HOST:-}" ]; then
    # Check to ensure we've got DB HOST, otherwise we'll use sqlite
    echo >&2 'warning: missing OCTOBER_DB_HOST, MYSQL_PORT_3306_TCP and POSTGRES_PORT_5432_TCP environment variables'
    echo >&2 '  Did you forget to --link some_db_container:db or set an external db'
    echo >&2 '  with -e OCTOBER_DB_HOST=hostname:port?'
    echo >&2 '===================='
    echo >&2 'Using sqlite instead'
    touch storage/database.sqlite && chown "$user:$group" storage/database.sqlite
    #exit 1
#        elif [ "${OCTOBER_DB_ALLOW_EMPTY_PASSWORD:-}" ne 'yes' && -z "${OCTOBER_DB_PASSWORD:-}" ]; then
#          # We have a DB HOST defined, so we're not using sqlite, but no password found
#          echo >&2 'error: missing required OCTOBER_DB_PASSWORD environment variable'
#          echo >&2 '  Did you forget to -e OCTOBER_DB_ALLOW_EMPTY_PASSWORD=true or  -e OCTOBER_DB_PASSWORD=... ?'
#          echo >&2
#          exit 1
  fi

        
	TERM=dumb php -- <<'EOPHP'
<?php
$driver = getenv('OCTOBER_DB_DRIVER');
$host = getenv('OCTOBER_DB_HOST');
$port = getenv('OCTOBER_DB_PORT');
$dbuser = getenv('OCTOBER_DB_USER');
$dbpass = getenv('OCTOBER_DB_PASSWORD');
$dbname = getenv('OCTOBER_DB_NAME');

$retries = 10;

switch($driver) {
  case 'mysql':
    while ($retries > 0)
    {
      try {
        $pdo = new PDO("mysql:host=$host;port=$port", $dbuser, $dbpass);
        $pdo->query("CREATE DATABASE IF NOT EXISTS $dbname");
        $retries = 0;
      } catch (PDOException $e) {
        $retries--;
        sleep(3);
      }
    }
    break;
  case 'pgsql':
    while ($retries > 0)
    {
      try {
        $pdo = new PDO("pgsql:host=$host;port=$port", 'postgres', $dbpass);
        // Postgres version of "CREATE DATABASE IF NOT EXISTS"
        $res = $pdo->query("select count(*) from pg_catalog.pg_database where datname = '$dbname';");
        if($res->fetchColumn() < 1)
          $pdo->query("CREATE DATABASE $dbname");

        $retries = 0;
      } catch (PDOException $e) {
        $retries--;
        sleep(3);
      }
    }
    break;
  default:
    $pdo = new PDO("sqlite:storage/database.sqlite");
    break;
}
EOPHP

# Export the variables so we can use them in config files
export OCTOBER_DB_DRIVER OCTOBER_DB_HOST OCTOBER_DB_PORT OCTOBER_DB_USER OCTOBER_DB_PASSWORD OCTOBER_DB_NAME



# Bring up the initial OctoberCMS database
echo "php artisan october:up"
php artisan october:up

# Update OctoberCMS to the latest version
echo "php artisan october:update"
php artisan october:update

# Install plugins if they are identified
IFS=';' read -ra OCTOBERPLUGIN <<< "${OCTOBER_PLUGINS:-}"
for i in "${OCTOBERPLUGIN[@]}"; do
    echo "php artisan plugin:install $i"
    php artisan plugin:install $i
done

# Install themes if they are identified
IFS=';' read -ra THEME <<< "${OCTOBER_THEMES:-}"
for i in "${THEME[@]}"; do
  echo "php artisan theme:install $i"
    php artisan theme:install $i
done


# BEGIN CLONE THEMES AND PLUGINS

# Install git plugins if they are identified
IFS=';' read -ra PLUGIN <<< "${GIT_PLUGINS:-}"
for i in "${PLUGIN[@]}"; do
  url_without_suffix="${i%.*}"
  reponame="$(basename "${url_without_suffix}")"
  hostname="$(basename "${url_without_suffix%/${reponame}}")"
  namespace="${hostname##*:}"

  echo "PLUGIN1: $reponame $hostname $namespace"

  # Only clone if it doesn't already exist
  if ! [ -e plugins/$namespace/$reponame ]; then
    echo "git clone $i $namespace/$reponame"
    (cd plugins && git clone $i $namespace/$reponame && chown -R $user:$group $namespace)
  fi
done

# Install git plugins if they are identified
IFS=';' read -ra PLUGINFOLDER <<< "${GIT_PLUGINS_FOLDER:-}"
for i in "${PLUGINFOLDER[@]}"; do
  basename=$(basename $i)
  repo=${basename%.*}
  reponame=${i##* }
  # echo "plugins folder repo doesn't exist!"
  # echo "$basename"
  # echo "$repo"
  # echo "$reponame"

  if [ -z $reponame ]; then
    reponame=$repo
  fi

  echo "PLUGIN2: $basename $repo $reponame $i"

  # Only clone if it doesn't already exist
  if ! [ -e plugins/$reponame ]; then
    echo "PLUGIN2: git clone $i"
    (cd plugins && git clone $i && chown -R $user:$group $reponame)

    for dir in plugins/$reponame/*; do
      echo "In $dir running composer install"
      echo "php artisan plugin:refresh $basename.$dir"
      (cd "$dir" && composer install && php artisan plugin:refresh $basename.$dir);
    done

    
  fi
done

# Install git themes if they are identified
IFS=';' read -ra THEME <<< "${GIT_THEMES:-}"
for i in "${THEME[@]}"; do
  basename=$(basename $i)
  repo=${basename%.*}
  reponame=${i##* }
  # echo "$basename"
  # echo "$repo"
  # echo "$reponame"
  if [ -z $reponame ]; then
    reponame=$repo
  fi
  echo "THEME: $basename $repo $reponame"

  # Only clone if it doesn't already exist
  if ! [ -e themes/$reponame ]; then
    echo "themes repo doesn't exist!"
    echo "git clone $i"
    (cd themes && git clone $i && chown -R $user:$group $reponame)
    # (cd themes/$reponame && composer install)
    (cd themes/$reponame && npm install && grunt)

  fi
done

chown -R $user:$group . 


# echo "chown directory $APACHE_RUN_USER : $APACHE_RUN_GROUP"
# chown -R $APACHE_RUN_USER:$APACHE_RUN_GROUP /var/www/html

# END CLONE THEMES AND PLUGINS


# Pull latest code from all plugin and theme git repos
# php artisan october:util git pull



# One last chown for good measure
# chown -R $user:$group /var/www/html


# added by Seb
# composer update

php artisan october:up

# we need npm for grunt
# npm install
# grunt



fi

exec "$@"
