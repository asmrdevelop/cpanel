package Whostmgr::Transfers::ArchiveManager::Subdomains;

# cpanel - Whostmgr/Transfers/ArchiveManager/Subdomains.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Try::Tiny;

use Cpanel::FileUtils::Read ();
use Cpanel::SafeDir         ();
use Cpanel::ArrayFunc       ();
use Cwd                     ();

sub retrieve_subdomains_from_extracted_archive {
    my ($archive_manager) = @_;

    my $utils        = $archive_manager->utils();
    my $extractdir   = $archive_manager->trusted_archive_contents_dir();
    my $archive_user = $archive_manager->get_username_from_extracted_archive();
    my $main_domain  = $utils->main_domain();
    my ( $uid, $gid, $user_homedir ) = ( $utils->pwnam() )[ 2, 3, 7 ];
    my $abshomedir = Cwd::abs_path($user_homedir);

    my $subdomains_file = Cpanel::ArrayFunc::first(
        sub { -e },
        ( map { "$extractdir/$_" } qw( sds2 sds ) )
    );

    if ( !$subdomains_file ) {
        return ( 0, "Failed to find a sds2 or sds file" );
    }

    my @subdomains;

    my $err;
    try {
        Cpanel::FileUtils::Read::for_each_line(
            $subdomains_file,
            sub {
                my $subdata = $_;

                $subdata =~ s/\n//g;
                my ( $fullsubdomain, $subdomain, $docroot, $rootdomain );
                if ( $subdata =~ m/=/ ) {
                    ( $fullsubdomain, $docroot ) = split( /=/, $subdata, 2 );
                    ( $subdomain, $rootdomain ) = split( /_/, $fullsubdomain );

                    if ( $docroot =~ m{^/} ) {
                        my $documentroot = $docroot;
                        my @docroot      = split /$archive_user/, $documentroot, 2;
                        $docroot = $docroot[1] if $docroot[1];
                    }

                    # Neither pollute global space nor be vulnerable
                    # other code’s pollution.
                    Cpanel::SafeDir::clearcache();
                    $docroot = Cpanel::SafeDir::safedir( $docroot, $user_homedir, $abshomedir );
                    Cpanel::SafeDir::clearcache();
                }
                else {
                    $fullsubdomain = $subdata;
                    ( $subdomain, $rootdomain ) = split( /_/, $fullsubdomain );
                    $docroot = $user_homedir . '/public_html/' . $subdomain;
                }
                $rootdomain ||= $main_domain;
                $fullsubdomain =~ s/_/\./g;

                if ($fullsubdomain) {
                    push @subdomains,
                      {
                        'subdomain'     => $subdomain,
                        'fullsubdomain' => $fullsubdomain,
                        'docroot'       => $docroot,
                        'rootdomain'    => $rootdomain
                      };
                }
            },
        );
    }
    catch { $err = $_ };

    return $err ? ( 0, $err->to_local_string() ) : ( 1, \@subdomains );
}

1;
