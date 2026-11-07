FROM php:8.2-apache 
WORKDIR /var/www/html 
RUN apt-get update && apt-get install -y libpq-dev libzip-dev unzip && docker-php-ext-install pdo_pgsql pdo_mysql zip 
RUN a2enmod rewrite 
COPY . /var/www/html 
RUN curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer 
RUN composer install --no-dev --no-interaction --no-progress 
ENV APACHE_DOCUMENT_ROOT /var/www/html/public 
RUN sed -ri -e 's!/var/www/html!$APACHE_DOCUMENT_ROOT!g' /etc/apache2/sites-available/*.conf 
RUN sed -ri -e 's!/var/www/!$APACHE_DOCUMENT_ROOT!g' /etc/apache2/apache2.conf /etc/apache2/conf-available/*.conf 
RUN echo '<Directory /var/www/html/public>\nOptions Indexes FollowSymLinks\nAllowOverride All\nRequire all granted\n' > /etc/apache2/conf-available/htaccess.conf && a2enconf htaccess 
EXPOSE 80 
