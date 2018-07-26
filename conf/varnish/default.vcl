# Self routing cluster example
vcl 4.0;

import directors;
import std;

backend node1 {
    .host = "node1.example.com";
    .port = "80";
}

backend node2 {
    .host = "node2.example.com";
    .port = "80";
}

backend node3 {
    .host = "node3.example.com";
    .port = "80";
}

backend node4 {
    .host = "node4.example.com";
    .port = "80";
}

probe check_web {
    .url = "/";
    .interval = 10s;
    .timeout = 6s;
    .window = 5;
    .threshold = 3;
}

backend content01 {
    .host = "nginx01.example.com";
    .port = "80";
    .probe = check_web;
}

backend content02 {
    .host = "nginx02.example.com";
    .port = "80";
    .probe = check_web;
}

acl allow_purge {
    "127.0.0.1";
    "localhost";
    "172.18.0.0/16";
}

sub vcl_init
{
    new cluster = directors.hash();
    cluster.add_backend(node1, 5);
    cluster.add_backend(node2, 5);
    cluster.add_backend(node3, 5);
    cluster.add_backend(node4, 5);

    new bcluster = directors.round_robin();
    bcluster.add_backend(content01);
    bcluster.add_backend(content02);
}

sub vcl_recv
{
    if (req.method == "PURGE") {
        if (!client.ip ~ allow_purge) {
            return (synth(405, "This IP is not allowed to send PURGE requests."));
        }
        return (purge);
    }

    # Store original url in temporary header
    set req.http.X-Original-Url = req.url;

    # strip out query string
    set req.url = regsub(req.url, "\?.*$", "");

    if (req.method != "GET" &&
        req.method != "HEAD" &&
        req.method != "PUT" &&
        req.method != "POST" &&
        req.method != "TRACE" &&
        req.method != "OPTIONS" &&
        req.method != "PATCH" &&
        req.method != "DELETE") {
        /* Non-RFC2616 or CONNECT which is weird. */
        return (pipe);
    }

    # Figure out where the content is
    set req.backend_hint = cluster.backend(req.url);
    set req.http.X-shard = req.backend_hint;

    # set req.http.grace = "none";

    # # Do we have the content? If yes, reroute to the backend
    # # If not, pass the request to the appropriate node
    if (req.http.X-shard == server.identity) {
        set req.backend_hint = bcluster.backend();
    } else {
        return(pass);
    }
}

sub vcl_hit
{
    set req.http.X-Cache-Keep = obj.keep;
    set req.http.X-Cache-TTL-Remaining = obj.ttl;
    set req.http.X-Cache-Age = obj.keep - obj.ttl;

    if (obj.keep - obj.ttl <= req.ttl) {
        set req.http.X-Cache-Result = "hit";
        return (deliver);
    }

    if ( std.healthy(req.backend_hint) ) {
        if (obj.keep - obj.ttl - 10s <= req.ttl) {
            set req.http.X-Cache-Result = "hit-with-slight-grace";
            return (deliver);
        } else {
            set req.http.X-Cache-Result = "stale-hit-so-fetch";
            return(fetch);
        }
    } else {
        if (obj.keep - obj.ttl - obj.grace <= req.ttl) {
            set req.http.X-Cache-Result = "hit-with-full-grace";
            return (deliver);
        } else {
            set req.http.X-Cache-Result = "stale-hit-so-fetch";
            return (fetch);
        }
    }
}

sub vcl_deliver
{
    unset resp.http.Via;
    unset resp.http.X-Powered-By;
    unset resp.http.X-Varnish;
    unset resp.http.Age;

    set resp.http.Server = "xxxx.yyy.zz";

    # set resp.http.grace = req.http.grace;

    # Uncomment to add hostname to headers
    set resp.http.X-Served-By = server.hostname;

    # Identify which Varnish handled the request
    if (obj.hits > 0) {
        set resp.http.X-Cache = "HIT from " + req.backend_hint;
    } else {
        set resp.http.X-Cache = "MISS from " + req.backend_hint;
    }

    set resp.http.X-Cache-Hits = obj.hits;

    # Remove version number sometimes set by CMS
    if (resp.http.X-Content-Encoded-By) {
        unset resp.http.X-Content-Encoded-By;
    }

    if (resp.http.magicmarker) {
        # Remove the magic marker, see vcl_fetch
        unset resp.http.magicmarker;

        # By definition we have a fresh object
        set resp.http.Age = "0";
    }

    if (req.http.X-Cache-Keep) {
        set resp.http.X-Cache-Keep = req.http.X-Cache-Keep;
    }
    if (req.http.X-Cache-TTL-Remaining) {
        set resp.http.X-Cache-TTL-Remaining = req.http.X-Cache-TTL-Remaining;
    }
    if (req.http.X-Cache-Age) {
        set resp.http.X-Cache-Age = req.http.X-Cache-Age;
    }
    if (req.http.X-Cache-TTL-Requested) {
        set resp.http.X-Cache-TTL-Requested = req.http.X-Cache-TTL-Requested;
    }
    if (req.http.X-Cache-Result) {
        set resp.http.X-CacheResult = req.http.X-Cache-Result;
    }

    return (deliver);
}

sub vcl_backend_response
{
    if (bereq.url ~ "\.(js|css|ts|image|png|jp(e?)g|png|gif|swf|pdf)(\?|$)") {
        set beresp.ttl = 3600s;
        unset beresp.http.Set-Cookie;
    } elseif (bereq.url ~ "/api" ) {
        set beresp.ttl = 10s;
        unset beresp.http.Set-Cookie;
    } else {
        set beresp.ttl = 120s;
    }

    set beresp.grace = 1h;
}
