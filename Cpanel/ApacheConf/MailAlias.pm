package Cpanel::ApacheConf::MailAlias;

# cpanel - Cpanel/ApacheConf/MailAlias.pm          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::AcctUtils::DomainOwner::Tiny ();
use Cpanel::Config::userdata::Guard      ();
use Cpanel::Config::userdata::Load       ();

sub add_mail_subdomain_for_user_domain {
    my ( $user, $domain ) = @_;

    die 'Need specific domain!' if !$domain;

    return _act_on_mail_subdomains_for_user( $user, \&_add_mail_subdomains_for_user, $domain );
}

#Run as root.
#Returns a boolean to indicate whether any work was done. If true,
#then Apache’s configuration needs to be rebuilt.
sub add_mail_subdomains_for_user {
    my ($user) = @_;

    return _act_on_mail_subdomains_for_user( $user, \&_add_mail_subdomains_for_user );
}

sub remove_mail_subdomain_for_user_domain {
    my ( $user, $domain ) = @_;

    die 'Need a domain!' if !$domain;
    die 'Need a user!'   if !$user;

    return _act_on_mail_subdomains_for_user( $user, \&_remove_mail_subdomains_for_user, $domain );
}

sub remove_mail_subdomains_for_user {
    my ($user) = @_;

    die 'Need a user!' if !$user;

    return _act_on_mail_subdomains_for_user( $user, \&_remove_mail_subdomains_for_user );
}

sub _act_on_mail_subdomains_for_user {
    my ( $user, $do_code_cr, $specific_domain ) = @_;

    my $user_userdata_dir = $Cpanel::Config::userdata::Constants::USERDATA_DIR . "/$user";
    if ( !-d $user_userdata_dir ) {
        warn "Unable to find the userdata directory for the user $user\n";
        return 0;
    }

    my $userdata      = Cpanel::Config::userdata::Load::load_userdata_main($user);
    my $domain_lookup = { $userdata->{main_domain} => [ $userdata->{main_domain}, @{ $userdata->{parked_domains} } ] };

    for my $addon ( keys %{ $userdata->{addon_domains} } ) {
        my $target = $userdata->{addon_domains}{$addon};
        $domain_lookup->{$target} ||= [];
        push @{ $domain_lookup->{$target} }, $addon;
    }

    return $do_code_cr->( $user, $domain_lookup, $specific_domain );
}

sub _add_mail_subdomains_for_user {
    my ( $user, $domain_lookup, $specific_domain ) = @_;

    my $need_to_rebuild_apache = 0;

    for my $file_domain ( keys %$domain_lookup ) {

        #We only want to add the mail subdomain if Apache doesn’t already have
        #a vhost that responds to that name.
        my $domains_ar = $domain_lookup->{$file_domain};
        if ($specific_domain) {
            @$domains_ar = grep { $_ eq $specific_domain } @$domains_ar;
        }
        @$domains_ar = grep { !_domain_already_exists_on_this_server("mail.$_") } @$domains_ar;

        if ( _add_mail_alias_to_vhost_userdata( $user, $file_domain, $domains_ar ) ) {
            $need_to_rebuild_apache ||= 1;
        }

        if ( Cpanel::Config::userdata::Load::user_has_ssl_domain( $user, $file_domain ) ) {
            if ( _add_mail_alias_to_vhost_userdata( $user, "${file_domain}_SSL", $domains_ar ) ) {
                $need_to_rebuild_apache ||= 1;
            }
        }
    }

    return $need_to_rebuild_apache ? 1 : 0;
}

sub _remove_mail_subdomains_for_user {
    my ( $user, $domain_lookup, $specific_domain ) = @_;

    my $need_to_rebuild_apache = 0;

    for my $file_domain ( keys %$domain_lookup ) {

        #We only want to add the mail subdomain if Apache doesn’t already have
        #a vhost that responds to that name.
        my $domains_ar = $domain_lookup->{$file_domain};
        if ($specific_domain) {
            @$domains_ar = grep { $_ eq $specific_domain } @$domains_ar;
        }

        if ( _remove_mail_alias_from_domain_userdata( $user, $file_domain, $domains_ar ) ) {
            $need_to_rebuild_apache ||= 1;
        }

        if ( Cpanel::Config::userdata::Load::user_has_ssl_domain( $user, $file_domain ) ) {
            if ( _remove_mail_alias_from_domain_userdata( $user, "${file_domain}_SSL", $domains_ar ) ) {
                $need_to_rebuild_apache ||= 1;
            }
        }
    }

    return $need_to_rebuild_apache ? 1 : 0;
}

#overridden in tests
sub _domain_already_exists_on_this_server {
    return Cpanel::AcctUtils::DomainOwner::Tiny::getdomainowner( $_[0], { skiptruelookup => 1, default => q<> } );
}

sub _add_mail_alias_to_vhost_userdata {
    my ( $user, $vhost_file, $domains_to_look_for ) = @_;

    my $updated = 0;

    my $guard          = Cpanel::Config::userdata::Guard->new( $user, $vhost_file );
    my $file_data      = $guard->data();
    my %server_aliases = map { $_ => 1 } split( q{ }, $file_data->{serveralias} );
    for my $domain (@$domains_to_look_for) {
        if ( !$server_aliases{$domain} && $file_data->{servername} ne $domain ) {
            warn "The expected server alias “$domain” doesn't exist in “$user”’s userdata file “$vhost_file”.";
            next;
        }

        $updated ||= !$server_aliases{"mail.$domain"};

        $server_aliases{"mail.$domain"} = 1;
    }

    if ($updated) {
        $file_data->{serveralias} = join( q{ }, sort keys %server_aliases );
        $guard->save();
    }

    #$guard will self-DESTROY on its own.

    return $updated;
}

sub _remove_mail_alias_from_domain_userdata {
    my ( $user, $domain_file, $domains_to_look_for ) = @_;

    my $updated = 0;

    my $guard          = Cpanel::Config::userdata::Guard->new( $user, $domain_file );
    my $file_data      = $guard->data();
    my %server_aliases = map { $_ => 1 } split( q{ }, $file_data->{serveralias} );

    for my $domain (@$domains_to_look_for) {
        if ( !$server_aliases{$domain} && $file_data->{servername} ne $domain ) {
            warn "The expected server alias “$domain” doesn't exist in “$user”’s userdata file “$domain_file”.";
            next;
        }

        if ( delete $server_aliases{"mail.$domain"} ) {
            $updated ||= 1;
        }
    }

    if ($updated) {
        $file_data->{serveralias} = join( q{ }, sort keys %server_aliases );
        $guard->save();
    }

    #$guard will self-DESTROY on its own.

    return $updated;
}

1;
