#!/usr/local/cpanel/3rdparty/bin/perl

# cpanel - whostmgr/docroot/cgi/news.cgi           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

package cgi::newsfeed;

use warnings;

use Cpanel::Logger                    ();
use Cpanel::LoadFile                  ();
use Cpanel::SafeFile                  ();
use Cpanel::SafeStorable              ();
use Cpanel::Template                  ();
use Encode                            ();
use HTTP::Date                        ();
use Cpanel::HTTP::Tiny::FastSSLVerify ();
use IO::Handle                        ();
use XML::LibXML                       ();
use XML::LibXML::XPathContext         ();

my $cache_file = '/var/cpanel/cpanelnews.cache';

if ( !caller() ) {
    my $result = __PACKAGE__->run();
    if ( !$result ) {
        exit 1;
    }
}

sub run {

    print "HTTP/1.0 200 OK\r\nContent-type: text/html; charset=\"utf-8\"\r\n\r\n";

    my @feed_urls = (
        'https://blog.cpanel.com/category/products/feed/',    # Articles about product dev
        'https://news.cpanel.com/feed/',                      # EOL and Security announcements
    );

    my $feed = get_news_feed( \@feed_urls );

    my $local_news = get_local_news();

    if ( ref $feed eq 'HASH' && !exists $feed->{'error'} ) {
        $feed->{'hasentries'} = 1;
    }

    Cpanel::Template::process_template(
        'whostmgr',
        {
            'template_file' => 'newsfeed.tmpl',
            'feed'          => $feed,
            'local_news'    => $local_news,
            'print'         => 1,
        }
    );
    exit;
}

#
# Get news data.
sub get_news_feed {
    my ($feed_urls) = @_;

    my $news_feed = get_news_cache();
    if ( !$news_feed ) {
        my %merged_feeds;
        foreach my $url (@$feed_urls) {
            my $feed = fetch_news_feed($url);
            if ( ref $feed eq 'HASH' || !$feed->{'error'} ) {
                @merged_feeds{ keys %{ $feed->{'entries'} } } = values %{ $feed->{'entries'} };
            }
        }
        if ( keys %merged_feeds ) {
            update_news_cache( \%merged_feeds );
            $news_feed = \%merged_feeds;
        }
    }

    return $news_feed;
}

#
# Read the data out of the news cache file, if the cache file is
# less than an hour old.
#
# Returns a feed hash if successful, undef if not.
sub get_news_cache {

    return unless -e $cache_file;

    # Only load from cache if it's less than an hour old.
    return if ( stat _ )[9] < time - 3600;

    my $fh   = IO::Handle->new();
    my $lock = Cpanel::SafeFile::safeopen( $fh, '<', $cache_file );
    return unless $lock;

    my $feed;
    my $logger;
    eval {
        $feed = Cpanel::SafeStorable::fd_retrieve($fh);
        1;
    } or do {
        $logger ||= Cpanel::Logger->new;
        $logger->warn("Failed to read news cache: $!");
        Cpanel::SafeFile::safeclose( $fh, $lock );
        return;
    };
    Cpanel::SafeFile::safeclose( $fh, $lock );
    return unless ref $feed eq 'HASH';    # || $feed->{'version_'} ne ( $version || '' );

    return $feed;
}

#
# Write the feed data to the cachefile.
sub update_news_cache {
    my ($feed) = @_;
    if ( ref $feed ne 'HASH' || $feed->{'error'} ) {
        unlink $cache_file if -e $cache_file;
        return;
    }
    my $fh   = IO::Handle->new();
    my $lock = Cpanel::SafeFile::safeopen( $fh, '>', $cache_file );

    my $logger;
    if ( !$lock ) {
        $logger ||= Cpanel::Logger->new();
        $logger->warn("Unable to create cache file '$cache_file': $!\n");
        return;
    }
    Storable::nstore_fd( $feed, $fh );
    Cpanel::SafeFile::safeclose( $fh, $lock );

    return;
}

#
# Request the appropriate kkk
sub fetch_news_feed {
    my ($url) = @_;
    my ( $news_url, $atom );

    $news_url = $url;
    $atom     = get_atom_feed($news_url);

    my $feed;
    my $logger;
    if ( !defined $atom ) {
        $feed = {
            'title' => 'News',
            'error' => 'Unable to load News at this time.',
        };
        $logger ||= Cpanel::Logger->new();
        $logger->warn("Unable to request cPanel News feed: $news_url");
    }
    else {
        my $xpc = XML::LibXML::XPathContext->new;
        $feed = extract_filtered_feed( $atom, $xpc );
    }
    $feed->{'self'} = $news_url;

    return $feed;
}

sub get_atom_feed {
    my ($url) = @_;

    my $http = Cpanel::HTTP::Tiny::FastSSLVerify->new();
    my $resp = $http->get($url);

    return unless $resp->{success};

    my $atom = $resp->{content};

    my $p    = XML::LibXML->new;
    my $root = eval { $p->parse_string($atom)->documentElement() };
    return if !defined $root || $root->nodeName() ne 'rss';

    return $root;
}

sub extract_filtered_feed {
    my ( $elem, $xpc ) = @_;

    my $feed;

    foreach my $c ( $xpc->findnodes( 'channel', $elem ) ) {

        foreach my $i ( $c->findnodes('item') ) {
            my ( $date, $entry ) = extract_entry( $i, $xpc );

            $feed->{'entries'}->{$date} = $entry;
        }
    }

    return $feed;
}

sub extract_entry {
    my ( $elem, $xpc ) = @_;

    my $date = HTTP::Date::str2time( ( $elem->findnodes('pubDate') )[0]->firstChild()->data() );
    my ( $d, $t ) = split( /\s/, HTTP::Date::time2iso($date) );
    my %entry = (
        'title'     => $xpc->findvalue( 'title', $elem ),
        'updated'   => format_time( $xpc->findvalue( 'atom:updated', $elem ) ),
        'published' => $d,
        'content'   => ( $elem->findnodes('description') )[0]->firstChild()->data(),
        'link'      => $xpc->findvalue( 'link',       $elem ),
        'author'    => $xpc->findvalue( 'dc:creator', $elem ),
        'type'      => 'info',
    );
    $entry{'uselink'} = 1;

    if ( $entry{'content'} =~ m/&#8230/i ) {
        my ( $wanted, undef ) = split( /&#8230/, $entry{'content'} );
        $entry{'content'} = $wanted;
    }

    if ( $entry{'link'} =~ m/^http:\/\/cpanel\.net/i ) {
        $entry{'type'} = 'warning';
    }

    %entry = map {
        my $val = $entry{$_};
        $_ => ( ref $val ? $val : Encode::encode( 'UTF-8', $val ) )
    } keys %entry;

    return ( $date, \%entry );
}

sub format_time {
    my ($stamp) = @_;
    my ( $date, $time ) = split /T/, $stamp;

    return $stamp unless defined $date && defined $time;

    $time =~ s/^(\d+:\d+):\d+Z$/$1 (UTC)/;
    return "$date, $time";
}

sub get_local_news {
    return Cpanel::LoadFile::loadfile('/var/cpanel/whmnews');
}

1;
