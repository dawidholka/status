ARG PHP_VERSION=8.2
ARG COMPOSER_VERSION=latest
ARG ROADRUNNER_VERSION=2.12.2

# Dependencies
FROM composer:${COMPOSER_VERSION} AS vendor
# Server
FROM spiralscout/roadrunner:${ROADRUNNER_VERSION} as roadrunner
# Application runtime
FROM php:${PHP_VERSION}-cli-alpine AS runtime

# Install composer
COPY --from=composer /usr/bin/composer /usr/bin/composer
# Install roadrunner
COPY --from=roadrunner /usr/bin/rr /usr/bin/rr

# Install packages and remove default server definition
RUN apk --no-cache add socat libzip-dev libpng-dev linux-headers pcre-dev libpq-dev ${PHPIZE_DEPS} \
    curl tzdata htop mysql-client dcron net-tools && \
    docker-php-ext-configure pgsql -with-pgsql=/usr/local/pgsql && \
    docker-php-ext-install pgsql pdo_pgsql exif pcntl zip gd mysqli pdo pdo_mysql bcmath ctype pdo_mysql pcntl sockets \
    && pecl install redis \
    && docker-php-ext-enable redis \
    && apk del pcre-dev ${PHPIZE_DEPS} \
    && rm -rf /tmp/pear

# Configure PHP-FPM
COPY docker/php.ini /etc/php8/conf.d/custom.ini

# Setup document root
RUN mkdir -p /var/www/html

# Make sure files/folders needed by the processes are accessable when they run under the nobody user
RUN chown -R nobody.nobody /var/www/html && \
  chown -R nobody.nobody /run

#RUN ln -sf /proc/1/fd/1 /var/log/octane.log #this is now working

COPY docker/php.ini "$PHP_INI_DIR/php.ini"

# Switch to use a non-root user from here on
USER nobody

# Add application
WORKDIR /var/www/html
COPY --chown=nobody . /var/www/html/

RUN rm -rf /var/www/html/node_modules

# Optimization
RUN composer install --optimize-autoloader --no-dev --no-interaction --no-ansi
# Install octane
RUN php artisan octane:install --server=roadrunner

# Expose the port roadrunner is reachable on
EXPOSE 8080

#RUN #php artisan route:cache

ENV OCTANE_WORKERS 4

# Start octane
CMD php artisan octane:roadrunner --port=8080 --host="0.0.0.0" --workers=$OCTANE_WORKERS --log-level=debug

# https://github.com/laravel/octane/issues/403#issuecomment-943401361
HEALTHCHECK CMD kill -0 `cat /var/www/html/storage/logs/octane-server-state.json | awk -F"[,:}]" '{for(i=1;i<=NF;i++){if($i~/'masterProcessId'\042/){print $(i+1)}}}' | tr -d '"' | sed -n 1p
