package Cpanel::Config::ModCpUserFile;

# cpanel - Cpanel/Config/ModCpUserFile.pm          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Debug               ();
use Cpanel::Config::CpUserGuard ();

sub adddomaintouser {
    my %OPTS = @_;
    my ( $user, $domain, $type ) = @OPTS{qw(user domain type)};

    return adddomainstouser(
        'user'    => $user,
        'domains' => [ lc $domain ],
        'type'    => $type
    );
}

sub adddomainstouser {
    my %OPTS = @_;
    my ( $user, $domains_ar, $type ) = @OPTS{qw(user domains type)};
    $type ||= '';

    if ( !$user || !@$domains_ar ) {
        Cpanel::Debug::log_warn('user or domains not specified, unable to add domain');
        return;
    }

    my $guard = Cpanel::Config::CpUserGuard->new($user);
    unless ($guard) {
        Cpanel::Debug::log_warn("Could not update user file for $user");
        return;
    }

    my %add_domains_index = map { $_ => 1 } @$domains_ar;
    my $changed           = 0;
    my $remove_key        = $type eq 'X' ? 'DOMAINS' : 'DEADDOMAINS';

    # being a DEADDOMAIN is mutally exclusive from being a DOMAIN
    # we remove it from the list if its in there
    if ( grep { $add_domains_index{$_} } @{ $guard->{'data'}->{$remove_key} } ) {
        $changed = 1;
        @{ $guard->{'data'}->{$remove_key} } = grep { !$add_domains_index{$_} } @{ $guard->{'data'}->{$remove_key} };
    }

    if ( $type eq 'X' ) {
        my %dead_domains_index = map { $_ => 1 } @{ $guard->{'data'}->{'DEADDOMAINS'} };

        # Don't save if domain is already present
        my @missing_dead_domains = grep { !$dead_domains_index{$_} } @$domains_ar;

        if ( !@missing_dead_domains ) {
            return 1 if !$changed;    # if we changed above we still need to save so we cannot return however we do not add the domain
        }
        else {
            push @{ $guard->{'data'}->{'DEADDOMAINS'} }, @missing_dead_domains;
        }
    }
    else {
        # Don't save if domain is already present
        my %domains_index = map { $_ => 1 } @{ $guard->{'data'}->{'DOMAINS'} };
        $domains_index{ $guard->{'data'}->{'DOMAIN'} } = 1;
        my @missing_domains = grep { !$domains_index{$_} } @$domains_ar;

        if ( !@missing_domains ) {
            return 1 if !$changed;    # if we changed above we still need to save so we cannot return however we do not add the domain
        }
        else {
            push @{ $guard->{'data'}->{'DOMAINS'} }, @missing_domains;
        }
    }

    return $guard->save();
}

sub removedomainfromuser {
    my %OPTS   = @_;
    my $user   = $OPTS{'user'};
    my $domain = lc $OPTS{'domain'};
    my $type   = $OPTS{'type'} || '';

    if ( !$user || !$domain ) {
        Cpanel::Debug::log_warn('user or domain not specified, unable to remove domain');
        return;
    }

    my $key = ( $type eq 'X' ? 'DEADDOMAINS' : 'DOMAINS' );

    my $guard = Cpanel::Config::CpUserGuard->new($user);
    unless ($guard) {
        Cpanel::Debug::log_warn("Could not update user file for $user");
        return;
    }

    if ( grep { $_ eq $domain } @{ $guard->{'data'}->{$key} } ) {
        @{ $guard->{'data'}->{$key} } = grep { $_ ne $domain } @{ $guard->{'data'}->{$key} };
        return $guard->save();
    }

    return 1;
}

1;
