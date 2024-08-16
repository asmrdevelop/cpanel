package Cpanel::SiteTemplates::Directory;

# cpanel - Cpanel/SiteTemplates/Directory.pm       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::PwCache ();

our $cpanel_template_directory   = '/usr/local/cpanel/3rdparty/share/site_templates';
our $root_template_directory     = '/var/cpanel/customizations/site_templates';
our $reseller_template_directory = '/var/cpanel/reseller/site_templates';

sub list_site_template_directories {
    my ($user) = @_;
    $user ||= $Cpanel::user;

    my @site_template_directories = ();
    if ( $user eq 'root' || $user eq 'system' ) {
        push @site_template_directories, $root_template_directory;
        push @site_template_directories, $cpanel_template_directory;
        return \@site_template_directories;
    }

    require Cpanel::Reseller;
    if ( Cpanel::Reseller::isreseller($user) ) {
        my $homedir = Cpanel::PwCache::gethomedir($user);
        push @site_template_directories, $homedir . $reseller_template_directory;
    }

    require Cpanel::AcctUtils::Owner;
    my $owner = Cpanel::AcctUtils::Owner::getowner($user);
    if ( $owner && $owner ne $user ) {
        push @site_template_directories, @{ list_site_template_directories($owner) };
    }
    else {    #reseller owns self
        push @site_template_directories, $root_template_directory;
        push @site_template_directories, $cpanel_template_directory;
    }

    return \@site_template_directories;
}

1;
