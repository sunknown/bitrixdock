FROM nginx:1.26.2

LABEL org.opencontainers.image.source="https://github.com/bitrixdock/bitrixdock"

COPY conf/nginx.conf /etc/nginx/
COPY conf/default.conf /etc/nginx/conf.d/
COPY conf/upstream.conf /etc/nginx/conf.d/

# Fix permissions for nginx cache directories
RUN chown -R www-data:www-data /var/cache/nginx /var/log/nginx

RUN usermod -u 1000 www-data

CMD ["nginx"]

EXPOSE 80 443
