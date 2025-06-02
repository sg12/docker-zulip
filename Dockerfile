# # This is a 2-stage Docker build. In the first stage, we build a
# # Zulip development environment image and use
# # tools/build-release-tarball to generate a production release tarball
# # from the provided Git ref.
# FROM ubuntu:24.04 AS base

# # Set up working locales and upgrade the base image
# ENV LANG="C.UTF-8"

# ARG UBUNTU_MIRROR

# RUN { [ ! "$UBUNTU_MIRROR" ] || sed -i "s|http://\(\w*\.\)*archive\.ubuntu\.com/ubuntu/\? |$UBUNTU_MIRROR |" /etc/apt/sources.list; } && \
#     apt-get -q update && \
#     apt-get -q dist-upgrade -y && \
#     DEBIAN_FRONTEND=noninteractive \
#     apt-get -q install --no-install-recommends -y \
#     ca-certificates git locales python3 sudo tzdata \
#     curl nodejs npm openssh-client && \
#     npm install -g corepack && \
#     corepack enable && \
#     touch /var/mail/ubuntu && chown ubuntu /var/mail/ubuntu && userdel -r ubuntu && \
#     useradd -d /home/zulip -m zulip -u 1000

# RUN corepack prepare pnpm@9.14.2 --activate

# FROM base AS build

# RUN echo 'zulip ALL=(ALL:ALL) NOPASSWD:ALL' >> /etc/sudoers

# WORKDIR /home/zulip

# # Указываем SSH URL и ветку
# ARG ZULIP_GIT_URL=git@github.com:sg12/connectRM.git
# ARG ZULIP_GIT_REF=develop

# # Копируем SSH-ключ и создаём обёртку для git
# COPY id_ed25519 /home/zulip/.ssh/id_ed25519
# RUN mkdir -p /home/zulip/.ssh && \
#     chmod 700 /home/zulip/.ssh && \
#     chmod 600 /home/zulip/.ssh/id_ed25519 && \
#     chown -R zulip:zulip /home/zulip/.ssh && \
#     echo '#!/bin/sh' > /home/zulip/git-ssh.sh && \
#     echo 'exec ssh -i /home/zulip/.ssh/id_ed25519 -o IdentitiesOnly=yes -o StrictHostKeyChecking=no "$@"' >> /home/zulip/git-ssh.sh && \
#     chmod +x /home/zulip/git-ssh.sh && \
#     GIT_SSH=/home/zulip/git-ssh.sh git clone --branch "$ZULIP_GIT_REF" "$ZULIP_GIT_URL" zulip && \
#     chown -R zulip:zulip /home/zulip/zulip  # Исправляем права после git clone

# # Переключаемся на пользователя zulip
# USER zulip

# WORKDIR /home/zulip/zulip

# ARG CUSTOM_CA_CERTIFICATES

# RUN corepack prepare pnpm@9.14.2 --activate

# RUN pnpm install --frozen-lockfile --prefer-offline

# RUN rm -rf node_modules/.cache

# # Отладка: проверяем ветку
# RUN git branch --show-current > /tmp/git_branch_check.txt

# # Finally, we provision the development environment and build a release tarball
# RUN SKIP_VENV_SHELL_WARNING=1 ./tools/provision --build-release-tarball-only

# RUN . /srv/zulip-py3-venv/bin/activate && \
#     ./tools/build-release-tarball docker && \
#     mv /tmp/tmp.*/zulip-server-docker.tar.gz /tmp/zulip-server-docker.tar.gz

# # In the second stage, we build the production image from the release tarball
# FROM base

# ENV DATA_DIR="/data"

# # Then, with a second image, we install the production release tarball.
# COPY --from=build /tmp/zulip-server-docker.tar.gz /root/
# COPY --from=build /tmp/git_branch_check.txt /root/
# COPY custom_zulip_files/ /root/custom_zulip

# ARG CUSTOM_CA_CERTIFICATES

# RUN \
#     # Make sure Nginx is started by Supervisor.
#     dpkg-divert --add --rename /etc/init.d/nginx && \
#     ln -s /bin/true /etc/init.d/nginx && \
#     mkdir -p "$DATA_DIR" && \
#     cd /root && \
#     tar -xf zulip-server-docker.tar.gz && \
#     rm -f zulip-server-docker.tar.gz && \
#     mv zulip-server-docker zulip && \
#     cp -rf /root/custom_zulip/* /root/zulip && \
#     rm -rf /root/custom_zulip && \
#     /root/zulip/scripts/setup/install --hostname="$(hostname)" --email="docker-zulip" \
#       --puppet-classes="zulip::profile::docker" --postgresql-version=14 && \
#     rm -f /etc/zulip/zulip-secrets.conf /etc/zulip/settings.py && \
#     apt-get -qq autoremove --purge -y && \
#     apt-get -qq clean && \
#     rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# COPY entrypoint.sh /sbin/entrypoint.sh
# COPY certbot-deploy-hook /sbin/certbot-deploy-hook

# VOLUME ["$DATA_DIR"]
# EXPOSE 80 443

# ENTRYPOINT ["/sbin/entrypoint.sh"]
# CMD ["app:run"]

# This is a 2-stage Docker build. In the first stage, we build a
# Zulip development environment image and use
# tools/build-release-tarball to generate a production release tarball
# from the provided Git ref.

FROM ubuntu:24.04 AS base

# Set up working locales and upgrade the base image
ENV LANG="C.UTF-8"

# Задаём зеркало mirror.yandex.ru и добавляем репозиторий PGroonga
RUN apt-get -q update && \
    apt-get -q install -y --no-install-recommends curl gnupg2 && \
    echo "deb http://mirror.yandex.ru/ubuntu/ noble main restricted universe multiverse" > /etc/apt/sources.list && \
    echo "deb http://mirror.yandex.ru/ubuntu/ noble-updates main restricted universe multiverse" >> /etc/apt/sources.list && \
    echo "deb http://mirror.yandex.ru/ubuntu/ noble-security main restricted universe multiverse" >> /etc/apt/sources.list && \
    echo "deb http://apt.postgresql.org/pub/repos/apt/ noble-pgdg main" >> /etc/apt/sources.list.d/pgdg.list && \
    curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor > /etc/apt/trusted.gpg.d/pgdg.gpg && \
    apt-get -q update && \
    apt-get -q dist-upgrade -y && \
    DEBIAN_FRONTEND=noninteractive \
    apt-get -q install --no-install-recommends -y \
        ca-certificates git locales python3 sudo tzdata \
        curl nodejs npm openssh-client \
        build-essential crudini default-jre-headless fonts-freefont-ttf \
        gettext hunspell-en-us jq libatk-bridge2.0-0 libffi-dev libgbm1 \
        libgtk-3-0 libldap2-dev libmagic1 libpq-dev libsasl2-dev libssl-dev \
        libvips libvips-tools libx11-xcb1 libxcb-dri3-0 libxml2-dev \
        libxmlsec1-dev libxslt1-dev libxss1 libyaml-dev memcached moreutils \
        pkg-config postgresql-16 postgresql-16-pgroonga puppet puppet-lint \
        python3-dev python3-pip rabbitmq-server redis-server supervisor unzip \
        virtualenv xdg-utils xvfb && \
    npm install -g corepack && \
    corepack enable && \
    touch /var/mail/ubuntu && \
    chown ubuntu /var/mail/ubuntu && \
    userdel -r ubuntu && \
    useradd -d /home/zulip -m zulip -u 1000 && \
    rm -rf /var/lib/apt/lists/*

RUN corepack prepare pnpm@9.14.2 --activate

FROM base AS build

RUN echo 'zulip ALL=(ALL:ALL) NOPASSWD:ALL' >> /etc/sudoers

WORKDIR /home/zulip

# Указываем SSH URL и ветку
ARG ZULIP_GIT_URL=git@github.com:sg12/connectRM.git
ARG ZULIP_GIT_REF=develop

# Копируем SSH-ключ и создаём обёртку для git
COPY id_ed25519 /home/zulip/.ssh/id_ed25519
RUN mkdir -p /home/zulip/.ssh && \
    chmod 700 /home/zulip/.ssh && \
    chmod 600 /home/zulip/.ssh/id_ed25519 && \
    chown -R zulip:zulip /home/zulip/.ssh && \
    echo '#!/bin/sh' > /home/zulip/git-ssh.sh && \
    echo 'exec ssh -i /home/zulip/.ssh/id_ed25519 -o IdentitiesOnly=yes -o StrictHostKeyChecking=no "$@"' >> /home/zulip/git-ssh.sh && \
    chmod +x /home/zulip/git-ssh.sh && \
    GIT_SSH=/home/zulip/git-ssh.sh git clone --branch "$ZULIP_GIT_REF" "$ZULIP_GIT_URL" zulip && \
    chown -R zulip:zulip /home/zulip/zulip

# Переключаемся на пользователя zulip
USER zulip

WORKDIR /home/zulip/zulip

ARG CUSTOM_CA_CERTIFICATES

RUN corepack prepare pnpm@9.14.2 --activate

RUN pnpm install --frozen-lockfile --prefer-offline

RUN rm -rf node_modules/.cache

# Отладка: проверяем ветку
RUN git branch --show-current > /tmp/git_branch_check.txt

# Выполняем provision с предварительной установкой всех пакетов
RUN SKIP_VENV_SHELL_WARNING=1 ./tools/provision --build-release-tarball-only

RUN . /srv/zulip-py3-venv/bin/activate && \
    ./tools/build-release-tarball docker && \
    mv /tmp/tmp.*/zulip-server-docker.tar.gz /tmp/zulip-server-docker.tar.gz

# In the second stage, we build the production image from the release tarball
FROM base

ENV DATA_DIR="/data"

# Then, with a second image, we install the production release tarball.
COPY --from=build /tmp/zulip-server-docker.tar.gz /root/
COPY --from=build /tmp/git_branch_check.txt /root/
COPY custom_zulip_files/ /root/custom_zulip

ARG CUSTOM_CA_CERTIFICATES

RUN \
    # Make sure Nginx is started by Supervisor.
    dpkg-divert --add --rename /etc/init.d/nginx && \
    ln -s /bin/true /etc/init.d/nginx && \
    mkdir -p "$DATA_DIR" && \
    cd /root && \
    tar -xf zulip-server-docker.tar.gz && \
    rm -f zulip-server-docker.tar.gz && \
    mv zulip-server-docker zulip && \
    cp -rf /root/custom_zulip/* /root/zulip && \
    rm -rf /root/custom_zulip && \
    /root/zulip/scripts/setup/install --hostname="$(hostname)" --email="docker-zulip" \
      --puppet-classes="zulip::profile::docker" --postgresql-version=14 && \
    rm -f /etc/zulip/zulip-secrets.conf /etc/zulip/settings.py && \
    apt-get -qq autoremove --purge -y && \
    apt-get -qq clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

COPY entrypoint.sh /sbin/entrypoint.sh
COPY certbot-deploy-hook /sbin/certbot-deploy-hook

VOLUME ["$DATA_DIR"]
EXPOSE 80 443

ENTRYPOINT ["/sbin/entrypoint.sh"]
CMD ["app:run"]
