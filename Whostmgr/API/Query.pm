#!/usr/local/cpanel/3rdparty/bin/perl

# cpanel - Whostmgr/API/Query.pm                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Whostmgr::API::Query;

use strict;

use Cpanel::HttpRequest::SSL ();    # do not use HTTP::Request::Common
use XML::Simple              ();    # already loaded in XML API, no need to hide it from perlcc
use Cpanel::JSON             ();    # already loaded in XML API, no need to hide it from perlcc
use Try::Tiny;

our $TIMEOUT = 10;

sub new {
    my ( $class, %opts ) = @_;

    my $self = bless {%opts}, $class;

    $self->{user} ||= 'root';

    # use JSON api as default as Cpanel::JSON is compiled in nearly all binaries
    $self->{api}      ||= 'json-api';
    $self->{hostname} ||= '127.0.0.1';
    $self->{port}     ||= 2087;
    $self->{retry}    ||= 3;

    die "hash undefined" unless $self->{hash};

    $self->{hash} =~ s/\n//g;
    $self->{hash} =~ s/^\s+//;
    $self->{hash} =~ s/\s+$//;

    die "invalid api method" if $self->{api} ne 'xml-api' && $self->{api} ne 'json-api';

    return $self;
}

sub httprequest {
    my ( $self, $method, $args ) = @_;

    return unless $method;

    my $opts;
    $opts = [%$args] if ref $args eq ref {};

    return $self->ua()->httppost(
        $self->{hostname},
        "$self->{api}/$method",
        $opts,
        undef,
        port    => $self->{port},
        headers => { 'Authorization' => $self->auth },
    );
}

sub query {
    my ( $self, $method, $args ) = @_;

    # wrap the request
    my ( $content, $err );
    try {
        $content = $self->httprequest( $method, $args );
    }
    catch {
        $err = $_;
    };

    if ($err) {
        return { 'error' => scalar $err };
    }

    return unless $content;

    my $hash;
    eval {
        if ( $self->{api} =~ /xml/i ) {
            local $XML::Simple::PREFERRED_PARSER = "XML::SAX::PurePerl";
            $hash = XML::Simple::XMLin($content);
        }
        else {
            $hash = Cpanel::JSON::Load($content);
            $hash = $hash->{cpanelresult} if $hash->{cpanelresult};
        }
    };

    $hash = {} unless defined $hash;
    return { 'error' => $hash->{metadata}->{reason} }                                  if $hash->{metadata} && exists $hash->{metadata}->{reason} && exists $hash->{metadata}->{result} && !$hash->{metadata}->{result};
    return { 'error' => "Cannot parse '" . $self->{api} . "'' content:\n" . $content } if $@;
    return $hash;
}

sub status {
    my ($self) = @_;

    my $r = $self->{result};
    return 0 unless $r && ref $r eq 'HASH';

    return $r->{result}{status} ? 1 : 0;
}

sub ua {
    my $self = shift;

    return $self->{_ua} if defined $self->{_ua};

    my $ua = Cpanel::HttpRequest::SSL->new(
        hideOutput       => 1,
        verify_hostname  => 0,
        http_retry_count => $self->{retry},
        timeout          => $TIMEOUT,
        die_on_error     => 1,
    );
    $self->{_ua} = $ua;

    return $ua;
}

sub auth {
    my ($self) = @_;

    return "WHM " . $self->{user} . ":" . $self->{hash};
}

1;
