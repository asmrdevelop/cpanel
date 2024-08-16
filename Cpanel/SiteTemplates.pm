package Cpanel::SiteTemplates;

# cpanel - Cpanel/SiteTemplates.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Cpanel::DomainLookup::DocRoot    ();
use Cpanel::JSON                     ();
use Cpanel::Logger                   ();
use Cpanel::SiteTemplates::Directory ();
use Cpanel::PwCache                  ();

my $logger = Cpanel::Logger->new();

sub list_site_templates {
    my ($user) = @_;
    $user ||= $Cpanel::user;

    my @list_templates = ();
    foreach my $dir ( @{ Cpanel::SiteTemplates::Directory::list_site_template_directories($user) } ) {
        next unless ( -d $dir && opendir my $dh, $dir );
        my @templates = grep { $_ !~ m{^\.} && -d $dir . '/' . $_ && -e $dir . '/' . $_ . '/meta.json' } readdir($dh);
        close $dh;

        foreach my $t (@templates) {
            my $meta      = {};
            my $meta_file = $dir . '/' . $t . '/meta.json';
            eval { $meta = Cpanel::JSON::LoadFile($meta_file) } or do {
                print STDERR $@;
                $logger->info( 'Invalid JSON found in site template at: ' . $meta_file );
                next;
            };

            push @list_templates, {
                'template' => $t,
                'preview'  => -e $dir . '/' . $t . '/preview.png' ? 1 : 0,
                'path'     => $dir,
                'meta'     => $meta
            };
        }
    }

    return \@list_templates;
}

sub list_user_settings {
    my ($user) = @_;
    $user ||= $Cpanel::user;

    my %list_domains = ();
    my %docroots     = Cpanel::DomainLookup::DocRoot::getdocroots($user);
    foreach my $domain ( keys %docroots ) {
        my $is_empty = 1;

        if ( opendir( my $dh, $docroots{$domain} ) ) {
            my @files = readdir $dh;
            close $dh;
            @files    = grep { $_ ne 'cgi-bin' && $_ !~ m/^\.+/ } @files;
            $is_empty = scalar @files ? 0 : 1;
        }

        my $homedir     = Cpanel::PwCache::gethomedir($user);
        my $config_dir  = $homedir . '/site_publisher/configurations';
        my $config_file = join( '-', split( /\/+/, $docroots{$domain} ) );
        $config_file =~ s{^-}{};
        $config_file .= '.json';
        $config_file = $config_dir . '/' . $config_file;

        unless ( -e $config_file ) {
            $config_file = $docroots{$domain} . '/configurations.json';
        }

        my $meta = {};
        if ( -r $config_file ) {
            eval { $meta = Cpanel::JSON::LoadFile($config_file) };
        }
        $meta->{'is_empty'} = $is_empty;

        $list_domains{$domain} = $meta;
    }

    return \%list_domains;
}

1;
