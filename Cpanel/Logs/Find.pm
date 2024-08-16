package Cpanel::Logs::Find;

# cpanel - Cpanel/Logs/Find.pm                     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

## no critic qw(TestingAndDebugging::RequireUseWarnings)

use Cpanel::ConfigFiles::Apache 'apache_paths_facade';    # see POD for import specifics
use Cpanel::WildcardDomain  ();
use Whostmgr::TweakSettings ();
use Cpanel::EA4::Constants  ();

our $VERSION           = '2.1';
our $checked_for_links = 0;
our @_log_locations;
my %FILE_EXISTS_CACHE;

our @_default_log_locations;

sub _default_log_locations {
    return @_default_log_locations if scalar @_default_log_locations;
    @_default_log_locations = (
        Cpanel::EA4::Constants::nginx_domain_logs_dir,    # UGMO: this must be first or Cpanel::Logd will fail to process ~/logs/ correctly
        '/var/domlogs',
        apache_paths_facade->dir_domlogs(),
        qw(
          /usr/local/apache/logs
          /usr/local/apache/var/logs
          /usr/local/apache/log
          /usr/local/apache/var/log
          /etc/httpd/domlogs
          /etc/httpd/logs
          /etc/httpd/log
        ),

        # only for unit tests
        @_
    );
    return @_default_log_locations;
}

sub find_wwwaccesslog {
    return find_logbyext( @_, '' ) || find_logbyext( @_, '-access_log' );
}

sub find_wwwaccesslog_with_info {
    my @ret = find_logbyext( $_[0], '', 1 );
    return @ret if @ret;
    return find_logbyext( $_[0], '-access_log', 1 );
}

sub find_ftpaccesslog {
    return find_logbyext( @_, '-ftp_log' );
}

sub find_ftpaccesslog_with_info {
    return find_logbyext( @_, '-ftp_log', 1 );
}

sub find_sslaccesslog {
    return find_logbyext( @_, '-ssl_log' );
}

sub find_sslaccesslog_with_info {
    return find_logbyext( $_[0], '-ssl_log', 1 );
}

sub find_wwwerrorlog {
    my $log = find_logbyext( @_, '-error_log' );
    if ( !-e $log || $log eq '' ) {
        if ( -e "/var/cpanel/apache2" && -e "/usr/local/apache2/logs/error_log" ) {
            return ('/usr/local/apache2/logs/error_log');
        }
        else {
            return ( apache_paths_facade->file_error_log() );
        }
    }
    return $log;
}

sub find_byteslog {
    return find_logbyext( @_, '-bytes_log' );
}

sub find_byteslog_backup {
    return find_logbyext( @_, '-bytes_log.bkup' );
}

sub find_popbyteslog {
    return find_logbyext( @_, '-popbytes_log' );
}

sub find_popbyteslog_backup {
    return find_logbyext( @_, '-popbytes_log.bkup' );
}

sub find_imapbyteslog {
    return find_logbyext( @_, '-imapbytes_log' );
}

sub find_imapbyteslog_backup {
    return find_logbyext( @_, '-imapbytes_log.bkup' );
}

sub find_ftpbyteslog {
    return find_logbyext( [ 'ftp.' . $_[0], $_[0] ], '-ftpbytes_log' );
}

sub find_ftplog {
    return find_logbyext( [ 'ftp.' . $_[0], $_[0] ], '-ftp_log' );
}

sub update_log_locations {
    my %seen;
    if ( !$checked_for_links ) {
        $checked_for_links = 1;
        my $httpd_base = apache_paths_facade->dir_base();
        if ( -l '/etc/httpd' && readlink('/etc/httpd') =~ m{^(../)?$httpd_base/?$} ) {
            @_default_log_locations = grep ( !m{^/etc/httpd/}, _default_log_locations() );
        }
    }
    @_log_locations = grep { -d $_ && !$seen{ join( ':', ( stat(_) )[ 0, 1 ] ) }++ } _default_log_locations();
}

sub cache_log_locations {
    update_log_locations() unless @_log_locations;
    foreach my $location (@_log_locations) {
        if ( opendir( my $log_dir_dh, $location ) ) {
            $FILE_EXISTS_CACHE{$location} = { map { $_ => undef } readdir($log_dir_dh) };

            # remove locations with no files
            if ( scalar keys %{ $FILE_EXISTS_CACHE{$location} } == 2 ) {    # just '.','..'
                @_log_locations = grep { $_ ne $location } @_log_locations;
            }
            close($log_dir_dh);
        }
    }
}

sub find_logbyext {
    my ( $domains, $hasext, $need_info ) = @_;
    update_log_locations() unless @_log_locations;

    my $pipedlogs = Whostmgr::TweakSettings::get_value( Main => "enable_piped_logs" );
    my $wantssl   = $hasext eq "-ssl_log";

    my $choice_count;
    foreach my $loc (@_log_locations) {
        my %CHOICES;

        my $ext      = $hasext;
        my $is_nginx = $loc eq Cpanel::EA4::Constants::nginx_domain_logs_dir ? 1 : 0;
        if ( $is_nginx && !$pipedlogs && $wantssl ) {
            $ext = "";
        }

        # Note: Cpanel::WildcardDomain::encode_wildcard_domain will return the wrong result for www.* domains
        # however they will just be ignored.  Its much faster to not have to remove them.
        foreach my $path (
            ref $domains
            ? ( map { ( Cpanel::WildcardDomain::encode_wildcard_domain("www.$_$ext"), Cpanel::WildcardDomain::encode_wildcard_domain("$_$ext") ) } @{$domains} )
            : ( Cpanel::WildcardDomain::encode_wildcard_domain("www.$domains$ext"), Cpanel::WildcardDomain::encode_wildcard_domain("$domains$ext") )
        ) {
            if ( exists $FILE_EXISTS_CACHE{$loc} ) {
                $CHOICES{"$loc/$path"} = [ ( stat("$loc/$path") )[ 7, 9 ] ] if exists $FILE_EXISTS_CACHE{$loc}->{$path};
            }
            elsif ( -e "$loc/$path" ) {
                $CHOICES{"$loc/$path"} = [ ( stat(_) )[ 7, 9 ] ];
            }
        }

        $choice_count = scalar keys %CHOICES;

        if ( $choice_count == 1 ) {
            my $choice = ( ( keys %CHOICES )[0] );
            return $need_info ? ( $choice, $CHOICES{$choice} ) : $choice;
        }
        elsif ($choice_count) {

            #choose the one with the newest mtime then size
            foreach my $choice ( sort { $CHOICES{$b}->[1] <=> $CHOICES{$a}->[1] || $CHOICES{$b}->[0] <=> $CHOICES{$a}->[0] } keys %CHOICES ) {
                return $need_info ? ( $choice, $CHOICES{$choice} ) : $choice;
            }
        }
    }
    return '';
}

1;
