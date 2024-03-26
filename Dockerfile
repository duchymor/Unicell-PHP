ARG PHP_VERSION
ARG DEBIAN_VERSION=bookworm
FROM php:${PHP_VERSION}-fpm-${DEBIAN_VERSION}

# User
ARG HOMEDIR=/var/www
ARG UID=1000
ARG GID=1000
ARG USERNAME=unicell
ARG USERGROUP=unicell
RUN groupadd -r -g $GID $USERGROUP && \
    useradd --no-log-init -r -s /usr/bin/bash -d $HOMEDIR -u $UID -g $GID $USERNAME && \
    rm -rf /var/www/html && \
    chown -R $UID:$GID $HOMEDIR

WORKDIR $HOMEDIR

# Basics
ARG DEFAULT_TOOLS="mc unzip"
ARG EXTRA_TOOLS=""
RUN set -eux; \
    if [ -n "$http_proxy" ]; then \
      pear config-set http_proxy ${http_proxy}; \
    fi; \
    pecl channel-update pecl.php.net; \
    apt-get update; \
    apt-get -y --no-install-recommends install \
    $DEFAULT_TOOLS \
    $EXTRA_TOOLS; \
    apt-get clean &&  \
    apt-get autoremove -y -f && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* /usr/share/doc/* && \
    rm /var/log/lastlog /var/log/faillog

# IPE (mlocati/docker-php-extension-installer)
ARG DEFAULT_EXTENSIONS="bcmath exif gd imagick/imagick@master imap intl mysqli opcache pgsql redis zip"
ARG EXTRA_EXTENSIONS=""
ENV IPE_GD_WITHOUTAVIF=1
ADD https://github.com/mlocati/docker-php-extension-installer/releases/latest/download/install-php-extensions /usr/local/bin/
RUN chmod +x /usr/local/bin/install-php-extensions && \
    install-php-extensions \
    $DEFAULT_EXTENSIONS \
    $EXTRA_EXTENSIONS

# Composer
USER $USERNAME
ENV COMPOSER_HOME="$HOMEDIR/.composer"
COPY --chown=$USERNAME:$USERGROUP composer/ ${COMPOSER_HOME}
ADD --chown=$USERNAME:$USERGROUP https://getcomposer.org/installer composer-setup.php
RUN php composer-setup.php && \
    php -r "unlink('composer-setup.php');"
USER root
RUN mv composer.phar /usr/local/bin/composer

# Configuration
COPY etc/php/ /usr/local/etc/php/

# Aliases
RUN echo "alias ls='ls -l --almost-all --color=auto --show-control-chars --full-time'" >> /etc/bash.bashrc
RUN echo "alias mc='EDITOR=mcedit mc'" >> /etc/bash.bashrc

# Nginx
ARG PROJECT_ROOT_BASE=project
ENV SSL_ENABLED=#
COPY --from=nginx /docker-entrypoint.d/ /

RUN apt-get update && \
    apt-get install -y lsb-release && \
    curl -o /etc/apt/trusted.gpg.d/php.gpg https://packages.sury.org/nginx/apt.gpg && \
    sh -c 'echo "deb https://packages.sury.org/nginx/ $(lsb_release -sc) main" > /etc/apt/sources.list.d/php.list' && \
    apt-get update && \
    apt-get install -y \
    nginx \
    gettext-base \
        # for envsubst (nginx)
    libfcgi-bin
        # for healhcheck (php-fpm)

# PHP-FPM healthcheck
RUN curl -o /usr/local/bin/php-fpm-healthcheck https://raw.githubusercontent.com/renatomefi/php-fpm-healthcheck/master/php-fpm-healthcheck \
    && chmod +x /usr/local/bin/php-fpm-healthcheck

# Configuration
COPY etc/php/ /usr/local/etc/php/
COPY etc/nginx/ /etc/nginx/
COPY etc/php-fpm.d/ /usr/local/etc/php-fpm.d/

RUN rm -f /usr/local/etc/php-fpm.d/www.conf && \
        # fix PHP-FPM startup notice
    chown -R $USERNAME:$USERGROUP /var/log && chgrp -R 0 /var/log && chmod -R g=u /var/log && \
        # fix nginx startup log check error
    chown -R $UID:$GID /etc/nginx/conf.d && \
        # allow nginx to process template
    rm -rf /var/www/html
        # remove default nginx directory

COPY --chmod=775 entrypoint.sh /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
CMD []
STOPSIGNAL SIGTERM

USER $USERNAME
ENV PROJECT_ROOT_BASE=$PROJECT_ROOT_BASE
WORKDIR "$HOMEDIR/$PROJECT_ROOT_BASE"

EXPOSE 8080
EXPOSE 443
