
FROM debian:bookworm

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    php8.2-fpm php8.2-mysql \
    mariadb-client curl ca-certificates && \
    rm -rf /var/lib/apt/lists/*

RUN curl -fsSL \
    https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar \
    -o /usr/local/bin/wp && \
    chmod +x /usr/local/bin/wp

COPY conf/www.conf /etc/php/8.2/fpm/pool.d/www.conf
COPY tools/init.sh /usr/local/bin/init.sh

RUN chmod +x /usr/local/bin/init.sh && \
    mkdir -p /run/php /var/www/html

# from this line run both build and run process.
WORKDIR /var/www/html

EXPOSE 9000

ENTRYPOINT ["/usr/local/bin/init.sh"]
CMD ["php-fpm8.2", "-F"]
