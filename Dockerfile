FROM php:8.2-apache 
WORKDIR /var/www/html 
RUN apt-get update && apt-get install -y libpq-dev libzip-dev unzip && docker-php-ext-install pdo_pgsql pdo_mysql zip 
RUN a2enmod rewrite 
COPY . /var/www/html 
RUN curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer 
RUN composer install --no-dev --no-interaction --no-progress 
RUN sed -i 's/DocumentRoot \/var\/www\/html/DocumentRoot \/var\/www\/html\/public/' /etc/apache2/sites-available/000-default.conf 
RUN sed -i '/<Directory \/var\/www\/>/,/<\/Directory>/ s/AllowOverride None/AllowOverride All/' /etc/apache2/apache2.conf 
EXPOSE 80 
