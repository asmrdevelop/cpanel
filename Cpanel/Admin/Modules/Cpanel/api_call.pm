#!/usr/local/cpanel/3rdparty/bin/perl

# cpanel - Cpanel/Admin/Modules/Cpanel/api_call.pm Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::Admin::Modules::Cpanel::api_call;

use strict;
use warnings;
use Cpanel::Team::AuditLog ();
use Cpanel::Exception      ();

use parent qw( Cpanel::Admin::Base );

=encoding utf-8

=head1 NAME

Cpanel::Admin::Modules::Cpanel::api_call

=head1 SYNOPSIS

  use Cpanel::AdminBin::Call ();

  Cpanel::AdminBin::Call::call ( "Cpanel", "api_call", "LOG", {} );

=head1 DESCRIPTION

This admin bin is used to log api calls as the adminbin user.

=cut

sub _actions {
    return qw(LOG READ);
}

use constant _allowed_parents => (
    __PACKAGE__->SUPER::_allowed_parents(),
    '/usr/local/cpanel/base/backend/elfinder_connector.cgi',
);

=head1 METHODS

=head2 LOG(JSON, API_TYPE)

Logs a serialized JSON structure to the api log file.

=head3 ARGUMENTS

=over

=item JSON - string

JSON data blob stored as string. Must not include any newline characters.

=item API_TYPE - restricted string

The API type (uapi,...)

=back

=head3 RETURNS

The success status of the write, either 1 or undef.

=cut

sub LOG {
    my ( $self, $call ) = @_;
    require Cpanel::Logger;
    require Cpanel::JSON;

    my $logger = Cpanel::Logger->new( { 'alternate_logfile' => '/usr/local/cpanel/logs/api_log' } );
    _validate_fields($call);

    my ( $called_by, $login_domain );
    if ( $ENV{'TEAM_USER'} || $ENV{'TEAM_LOGIN_DOMAIN'} ) {
        $called_by    = $self->get_caller_team_user();
        $login_domain = $self->get_caller_team_user_login_domain();
    }
    else {
        $called_by = $self->get_caller_username();
    }
    my $api_version = exists $call->{'api_version'} ? $call->{'api_version'} : '';

    my $line = 'api_version=' . $api_version . ' ';
    $line .= 'called_by=' . $called_by . ' ';
    $line .= 'login_domain=' . $login_domain . ' ' if length $login_domain;

    delete $call->{'api_version'};    # avoid duplication
    $line .= eval { Cpanel::JSON::canonical_dump($call) };

    $logger->info($line);

    return;
}

sub READ {
    my ($self)     = @_;
    my $team_owner = $self->get_caller_username();
    my @audit_log  = eval { Cpanel::Team::AuditLog::get_api_log($team_owner) };
    die Cpanel::Exception::create( 'AdminError', [ message => Cpanel::Exception::get_string_no_id($@) ] ) if $@;
    return \@audit_log;
}

sub _validate_fields {
    my $call           = shift;
    my %allowed_fields = (
        'api_version' => 1,
        'call'        => 1,
        'uri'         => 1,
        'page'        => 1
    );

    foreach my $field ( keys %$call ) {
        delete $call->{$field} if ( !exists $allowed_fields{$field} );
    }
    return;
}
1;
