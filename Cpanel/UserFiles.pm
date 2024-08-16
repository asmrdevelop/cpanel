package Cpanel::UserFiles;

# cpanel - Cpanel/UserFiles.pm                     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Cpanel::ConfigFiles ();
use Cpanel::PwCache     ();

sub security_policy_files {
    my ($user) = @_;

    return unless defined $user;

    my $secpol_dir = user_security_policy_dir($user);
    return map { "$secpol_dir/$_" } ( "iplist/$user", "iplist/$user.cache", "questions/$user", "questions/$user.json" );
}

sub old_security_policy_files {
    my ( $olduser, $newuser ) = @_;

    return unless defined $olduser;
    return unless defined $newuser;

    my $secpol_dir = user_security_policy_dir($newuser);
    return map { "$secpol_dir/$_" } ( "iplist/$olduser", "iplist/$olduser.cache", "questions/$olduser", "questions/$olduser.json" );
}

sub user_security_policy_dir {
    my ($user) = @_;
    my $homedir;

    if ( $user eq 'cpanel' || $user eq 'root' ) {
        $homedir = $Cpanel::ConfigFiles::ROOT_CPANEL_HOMEDIR;
    }
    else {
        $homedir = ( Cpanel::PwCache::getpwnam($user) )[7];

        #TODO: This should probably happen.
        #die "User “$user” does not exist!" if !$homedir;
    }

    return $homedir . '/.cpanel/securitypolicy';
}

sub homedir_security_policy_dir {
    my ($homedir) = @_;

    # Use 'special' home directory, if /root is supplied.
    return "$Cpanel::ConfigFiles::ROOT_CPANEL_HOMEDIR/.cpanel/securitypolicy" if $homedir eq '/root';
    return $homedir . '/.cpanel/securitypolicy';
}

sub userconfig_path {
    my ($user) = @_;

    return unless $user;
    return "/var/cpanel/userconfig/$user";
}

sub userconfig_files {
    my ($user) = @_;

    return unless $user;

    return unless my $dir = userconfig_path($user);
    return unless opendir( my $dh, $dir );

    my @ret = map { "$dir/$_" } grep { $_ ne '.' && $_ ne '..' } readdir($dh);

    closedir($dh);

    return @ret;
}

sub public_html_symlinks_file {
    my ($user) = @_;

    return unless $user;
    return unless my $path = userconfig_path($user);
    return "$path/public_html_symlinks";
}

sub dkim_key_files_for_domain {
    my ($domain) = @_;

    die 'need domain!' if !length $domain;

    return ( "$Cpanel::ConfigFiles::DOMAIN_KEYS_ROOT/public/$domain", "$Cpanel::ConfigFiles::DOMAIN_KEYS_ROOT/private/$domain" );
}

1;    # Magic true value required at end of module
