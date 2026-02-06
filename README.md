# README

This is the README for the Bedrock Autocomplete example.

# Overview

The sample application is designed to show you how to use the
Autocomplete handler included with Bedrock. The Apache handler is one of the
components required to implement autocompletion - the ability for your
web application to present choices to users based on a few
characters. For example, given a list of bird names in a list if I
search the list for birds that start with 'co' I might expect to see
the choices:

* Common Loon
* Common Grackle
* Cormorant

# Components Required For Autocompletion

1. The Autocomplete handler: `Bedrock::Service::Autocomplete` (included
   with Bedrock)
2. Apache directive that configures the handler (if running under Apache)
3. A JSON file containing the list of items
4. A web page containing a form to enter queries
5. A Javascript function that makes the AJAX call to the handler
6. An optional `autocomplete.xml` configuration file

## Autocomplete Handler

The handler is enabled when you add a directive to the Apache
configuration file. The handler can be installed as a `mod_perl`, CGI
or `bedrock-miniserver.pl` handler.

### Apache Handlers

```
Action bedrock-autocomplete /cgi-bin/bedrock-service.cgi virtual

Alias /autocomplete /var/www/bedrock/autocomplete>

<Directory /autocomplete>
  AcceptPathInfo On
  Options -Indexes

  <IfModule mod_perl.c>
    SetHandler modperl
    PerlResponseHandler Bedrock::Service::Autocomplete
  </IfModule>

  <IfModule !mod_perl.c>
    SetHandler bedrock-autocomplete
    SetEnv BEDROCK_SERVICE_NAME Bedrock::Service::Autocomplete
  </IfModule>

</Directory>
```

After configuring an Autocomplete directory, add your Autocomplete
JSON files. If all you need to do is serve Autocomplete files from the
user's session directory you do not need the `Alias` directive. The
search order for finding Autocomplete files will eventually look in
a users session directory.

### `bedrock-miniserver.pl`

To run a lightweight HTTP server that support Bedrock services just
use the miniserver!

 bedrock-miniserver.pl -c birds.yml
 curl http::/localhost/birds
 
## JSON Autocomplete File

The format of the file is mostly up to you but should be at least an
array of hashes where you terms are found using the key `label` by default.
The entire row will be returned to you when a match occurs. To use a
different key as the target of your search set the the value
`search_key` in your `autocomplete.xml` file.

```
[
  { "label" : "Bedrock", "value" : "1" },
  { "label" : "Perl",    "value" : "2"}
]
```

See `perldoc Bedrock::Service::Autocomplete` for more information.

## Web Form

Add some kind of input area so your users can enter a search term. On
submit you should invoke a Javascript function uses an AJAX call to
invoke the handler.

```
<label for="search">Search:</label>
<input type="text" id="search" placeholder="Search for a bird...">
```

## Javascript Autocomplete Function

Here's an example of using jQuery's `autocomplete()` function:

```
//----------------------------------------------------------------------
$(function () {
//----------------------------------------------------------------------
  let lastSelectedItem = null;

  $("#search").autocomplete({
    source: function (request, response) {
      $.ajax({
        url: "/autocomplete/birds.json", // adjust this path to your backend
        data: { term: request.term },
        success: function (data) {
          response(data); // expect array of { label, image_url }
        }
      });
    },
    focus: function (event, ui) {
      event.preventDefault();
      $("#search").val(ui.item.label);
    },
    select: function (event, ui) {
      event.preventDefault();
      $("#search").val(ui.item.label);
      showBirdCard(ui.item);
    },
    minLength: 2
  });
```

...but of course feel free to roll your own.

## `autocomplete.xml`

You can set various options in a configuration file that will control
the Autocomple handler's behavior.  See `perldoc
Bedrock::Service::Autocomplete` for details.

```
<object>
  <object name="autocomplete">
    <scalar name="insecure">no</scalar>
    <scalar name="search_key">term</scalar>
    <scalar name="cache">yes</scalar>
    <scalar name="enabled">yes</scalar>
  </object>
</object>
```

Drop this file in Bedrock's configuration directory.

# Creating the List

Our example implementation allows you to enter a search term
representing the name of a bird. The `fetch-bird-images.pl` script is
used to search the https://commons.wikipedia.org site for bird
images. For each bird we find from our master list of birds
(`birds.txt`) we create an entry in our array of hashes that
represents our Autocomplete file. Use the `Makefile` provided to
create or update the list.

```
make SLEEP=45
```

Why `SLEEP=45`? If you bang https://commons.wikipedia.org too hard
you'll get blocked, so use a sleep value to throttle requests. Even 45
might be too quick. YMMV.

Files are downloaded to the `images/jpg` directory and then resized as
`.png` files to use in our example application.

The `Makefile` will download the images, resize them and then create
`.zip` file you can deploy to the Bedrock Docker image found on
[Dockerhub](https://hub.docker.com/r/rlauer/openbedrock).

# Installing the Example Application

Bring up Bedrock from the Docker image. Use the `docker-compose` and
Dockerfiles found here:
[`docker-compose.yml'](https://github.com/rlauer6/openbedrock/blob/master/docker)

`OS=al2023 DOCKERIMAGE=bedrock-$OS DOCKERFILE=Dockerfile.bedrock-$OS docker compose up`

After bringing up Bedrock, copy and install the ZIP file:

```
docker cp autocomplete-example.zip docker-web-1:/
docker exec docker-web-1 unzip /autocomplete-example.zip -d /
```

...now visit http://localhost/birds (or http://localhost:8080/birds if
you tunneling).  Type a search term like `blu` and select a bird!
