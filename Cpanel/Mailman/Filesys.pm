package Cpanel::Mailman::Filesys;

# cpanel - Cpanel/Mailman/Filesys.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Cpanel::ConfigFiles        ();
use Cpanel::Mailman::NameUtils ();

sub CONFIGCACHE_DIR_REL_HOMEDIR {
    return "/.cpanel/caches/mailmanconfig";
}

sub MAILMAN_DIR {
    return $Cpanel::ConfigFiles::MAILMAN_ROOT;
}

sub MAILMAN_ARCHIVE_DIR {
    return MAILMAN_DIR() . '/archives/private';
}

sub MAILMAN_ARCHIVE_PUBLIC_DIR {
    return MAILMAN_DIR() . '/archives/public';
}

sub MAILING_LISTS_DIR {
    return MAILMAN_DIR() . '/lists';
}

sub SUSPENDED_LISTS_DIR {
    return MAILMAN_DIR() . '/suspended.lists';
}

#Pass in either listname_domain.org or listname@domain.org
sub get_list_dir {
    my ($list) = @_;

    $list = Cpanel::Mailman::NameUtils::normalize_name($list);

    return MAILING_LISTS_DIR() . "/$list";
}

sub get_suspended_list_dir {
    my ($list) = @_;

    $list = Cpanel::Mailman::NameUtils::normalize_name($list);

    return SUSPENDED_LISTS_DIR() . "/$list";
}

sub does_list_exist {
    my ( $list, $domain ) = @_;

    for ( $list, $domain ) {
        die "Need list and domain!" if !length;
    }

    #Invalid list name, but that doesn't mean that we can't say
    #that such a list doesn't exist, so don't throw an exception.
    for ( $list, $domain ) {
        return if m{/|^\.};
    }

    my $full_name = Cpanel::Mailman::NameUtils::make_name( $list, $domain );

    return -d get_list_dir($full_name) ? 1 : 0;
}

#Same as does_list_exist(), but you pass in the list name as a single string,
#with name/domain joined with an at-sign or underscore.
sub does_full_list_exist {
    my ($full_name) = @_;

    die "Need full list (joined w/ _ or @)!" if !length $full_name;

    return if $full_name =~ m</|^\.>;

    $full_name = Cpanel::Mailman::NameUtils::normalize_name($full_name);

    return -d get_list_dir($full_name) ? 1 : 0;
}

sub does_full_suspended_list_exist {
    my ($full_name) = @_;

    die "Need full list (joined w/ _ or @)!" if !length $full_name;

    return if $full_name =~ m</|^\.>;

    $full_name = Cpanel::Mailman::NameUtils::normalize_name($full_name);

    return -d get_suspended_list_dir($full_name) ? 1 : 0;
}

#Pass in either a single domain or an array-ref of domains.
sub get_list_ids_for_domains {
    my ($domains_ar) = @_;
    return _get_list_ids_for_domains_in_directory( $domains_ar, MAILING_LISTS_DIR() );
}

sub get_suspended_list_ids_for_domains {
    my ($domains_ar) = @_;
    return _get_list_ids_for_domains_in_directory( $domains_ar, SUSPENDED_LISTS_DIR() );
}

sub _get_list_ids_for_domains_in_directory {
    my ( $domains_ar, $directory ) = @_;

    if ( !ref $domains_ar ) {
        $domains_ar = [$domains_ar];
    }

    my %domains_lookup = map { $_ => undef } @$domains_ar;

    my @lists;

    if ( -d $directory ) {
        opendir( my $lists_dh, $directory ) or do {
            return ( 0, $! );
        };

        @lists = grep { tr{_}{} && exists $domains_lookup{ ( split( m{_}, $_ ) )[-1] } } readdir($lists_dh);

        closedir $lists_dh or warn $!;
    }

    return ( 1, \@lists );
}

1;
