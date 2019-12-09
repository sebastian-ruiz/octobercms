# OctoberCMS - Docker Container

# !!! Under Construction !!!

### Prerequisites

1. [Install docker](https://www.digitalocean.com/community/tutorials/how-to-install-and-use-docker-on-ubuntu-18-04)
2. [Install docker-compose](https://www.digitalocean.com/community/tutorials/how-to-install-docker-compose-on-ubuntu-16-04)

### Quick install guide

1. `git clone git@github.com:sebastian-ruiz/octobercms.git`
2. `cd octobercms`
3. `cp .env.sample .env`
4. Edit `.env` appropriately
5. `docker-compose up -d`

Then

6. Go to `http://localhost:8080`


### View logs

- `docker-compose logs`
- or use [Portainer](https://www.portainer.io/)