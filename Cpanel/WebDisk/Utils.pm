package Cpanel::WebDisk::Utils;

# cpanel - Cpanel/WebDisk/Utils.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Debug    ();
use Cpanel::SafeFile ();

sub _change_webdisk_domainname {
    my ( $homedir, $olddomain, $newdomain ) = @_;

    if ( $> == 0 ) {
        require Cpanel::Locale;
        my $locale = Cpanel::Locale->get_handle();
        return ( 0, $locale->maketext( '“[_1]” must not be run as [output,class,root,code].', '_change_webdisk_domainname' ) );
    }

    ## domainname might be contained in webdisk virtual user's name;
    ##   changing relevant entries in $homedir/etc/webdav/passwd
    {
        my $fname = "$homedir/etc/webdav/passwd";
        if ( -e $fname ) {

            # TODO: convert to using Cpanel::Transaction::File::Raw
            my $slock = Cpanel::SafeFile::safeopen( my $passwd_fh, '+<', $fname );
            if ( !$slock ) {
                Cpanel::Debug::log_info("Could not read from $fname: $!");
                return;
            }
            _change_webdisk_domainname_passwd_fh( $passwd_fh, $olddomain, $newdomain, $homedir );
            Cpanel::SafeFile::safeclose( $passwd_fh, $slock );
        }
    }

    ## domainname might be contained in webdisk virtual user's name; changing
    ##   relevant entries in $homedir/etc/webdav/shadow; in addition, since
    ##   the old domain name and user's password is contained in the digest
    ##   auth hash (and we do not have the password), we must remove/disable
    ##   digest auth

    ## accumulate the names of webdisk virtual users who will have digest
    ##   auth disabled
    my @digest_disabled;
    {
        my $fname = "$homedir/etc/webdav/shadow";
        if ( -e $fname ) {

            # TODO: convert to using Cpanel::Transaction::File::Raw
            my $slock = Cpanel::SafeFile::safeopen( my $shadow_fh, '+<', $fname );
            if ( !$slock ) {
                Cpanel::Debug::log_info("Could not read from $fname: $!");
                return;
            }
            _change_webdisk_domainname_shadow_fh( $shadow_fh, $olddomain, $newdomain, $homedir, \@digest_disabled );
            Cpanel::SafeFile::safeclose( $shadow_fh, $slock );
        }
    }
    return \@digest_disabled;
}

sub _change_webdisk_username {
    my ( $oldhomedir, $newhomedir ) = @_;

    if ( $> == 0 ) {
        require Cpanel::Locale;
        my $locale = Cpanel::Locale->get_handle();
        return ( 0, $locale->maketext( '“[_1]” must not be run as [output,class,root,code].', '_change_webdisk_username' ) );
    }

    my $fname = "$newhomedir/etc/webdav/passwd";
    if ( -e $fname ) {

        # TODO: convert to using Cpanel::Transaction::File::Raw
        my $slock = Cpanel::SafeFile::safeopen( my $passwd_fh, '+<', $fname );
        if ( !$slock ) {
            Cpanel::Debug::log_info("Could not read from $fname: $!");
            return;
        }
        ## change the homedir for each webdisk virtual user in $homedir/etc/webdav/passwd
        _change_webdisk_username_passwd_fh( $passwd_fh, $oldhomedir, $newhomedir );
        Cpanel::SafeFile::safeclose( $passwd_fh, $slock );
    }
    return 1;
}

sub _change_webdisk_username_passwd_fh {
    my ( $passwd_fh, $oldhomedir, $newhomedir ) = @_;

    my @changed_lines;
    while ( my $line = <$passwd_fh> ) {
        chomp($line);
        my @vals = split( /:/, $line );
        $vals[5] =~ s/^$oldhomedir/$newhomedir/;
        push( @changed_lines, join( ':', @vals ) );

        require Cpanel::PwFileCache;
        Cpanel::PwFileCache::clearcache(
            {
                'passwd_cache_dir'  => "$newhomedir/etc/webdav/\@pwcache",
                'passwd_cache_file' => $vals[0],
            }
        );
    }

    ## each line was changed; this is not conditional
    seek( $passwd_fh, 0, 0 );
    print {$passwd_fh} join( "\n", @changed_lines ) . "\n";
    truncate( $passwd_fh, tell($passwd_fh) );
    return;
}

sub _change_webdisk_domainname_passwd_fh {
    my ( $passwd_fh, $olddomain, $newdomain, $homedir ) = @_;

    my ( @changed_lines, $changed );
    while ( my $line = <$passwd_fh> ) {
        chomp($line);
        my @vals         = split( /:/, $line );
        my $old_virtuser = $vals[0];
        ## anchor with \b so that it works on both domain entries and subdomain
        if ( $vals[0] =~ m/\b$olddomain$/ ) {
            $changed = 1;
            $vals[0] =~ s/\b$olddomain$/$newdomain/;

            require Cpanel::PwFileCache;
            Cpanel::PwFileCache::clearcache(
                {
                    'passwd_cache_dir'  => "$homedir/etc/webdav/\@pwcache",
                    'passwd_cache_file' => $old_virtuser,
                }
            );
        }
        push( @changed_lines, join( ':', @vals ) );

    }
    if ($changed) {
        seek( $passwd_fh, 0, 0 );
        print {$passwd_fh} join( "\n", @changed_lines ) . "\n";
        truncate( $passwd_fh, tell($passwd_fh) );
    }
    return;
}

sub _change_webdisk_domainname_shadow_fh {
    my ( $shadow_fh, $olddomain, $newdomain, $homedir, $digest_disabled_ref ) = @_;

    my ( @changed_lines, $changed );
    while ( my $line = <$shadow_fh> ) {
        chomp($line);
        my @vals         = split( /:/, $line, 9 );
        my $old_virtuser = $vals[0];
        ## anchor with \b so that it works on both domain entries and subdomain
        if ( $vals[0] =~ m/\b$olddomain$/ ) {
            $changed = 1;
            $vals[0] =~ s/\b$olddomain$/$newdomain/;
            ## clear out digest auth, as $olddomain is embedded in the hash and
            ##   we do not have the password
            unless ( $vals[8] =~ m/^\s*$/ ) {
                push( @$digest_disabled_ref, $vals[0] );
                $vals[8] = '';
            }

            require Cpanel::PwFileCache;
            Cpanel::PwFileCache::clearcache(
                {
                    'passwd_cache_dir'  => "$homedir/etc/webdav/\@pwcache",
                    'passwd_cache_file' => $old_virtuser,
                }
            );
        }
        push( @changed_lines, join( ':', @vals ) );
    }

    if ($changed) {
        seek( $shadow_fh, 0, 0 );
        my $contents = join( "\n", @changed_lines ) . "\n";
        print {$shadow_fh} $contents;
        truncate( $shadow_fh, tell($shadow_fh) );
    }
    return;
}

1;
