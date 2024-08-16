package Cpanel::ConfigFiles::Httpd;

# cpanel - Cpanel/ConfigFiles/Httpd.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

#----------------------------------------------------------------------

# These should not be changed, only exposed for the purpose of testing.
our $apache2_marker = '/var/cpanel/apache2';
our $apache2_srm    = '/usr/local/apache2/conf/srm.conf';
our $default_srm    = '/etc/httpd/conf/srm.conf';
our $apache2_mime   = '/usr/local/apache2/conf/mime.types';
our $default_mime   = '/etc/httpd/conf/mime.types';

#----------------------------------------------------------------------

sub stat_httpconf {
    my $file = find_httpconf();
    my @stat = stat(_);
    return wantarray ? ( $file, \@stat ) : $file;
}

# This MUST stat the file since _ is used later
sub find_httpconf {
    my $force = shift;
    require Cpanel::ConfigFiles::Apache;    # using Cpanel::LoadModule w/ add 450 to RSS which deviates from the intent of this being a lightweight way to know where all the config files are
    my $httpd_conf_file = Cpanel::ConfigFiles::Apache::apache_paths_facade()->file_conf();

    #CANNOT use wantarray here
    if ( -e $httpd_conf_file || ( defined $force && $force >= 2 ) ) {
        return $httpd_conf_file;
    }
    die "Unable to locate httpd.conf ($httpd_conf_file)" if !$force;
    return;
}

sub stat_srmconf {
    my $file = find_srmconf();
    my @stat = stat(_);
    return wantarray ? ( $file, \@stat ) : $file;
}

sub get_srmconf {
    require Cpanel::ConfigFiles::Apache;    # using Cpanel::LoadModule w/ add 450 to RSS which deviates from the intent of this being a lightweight way to know where all the config files are
    my $apache_srm = Cpanel::ConfigFiles::Apache::apache_paths_facade()->file_conf_srm_conf();
    return $apache_srm;
}

sub get_mimetypes {
    require Cpanel::ConfigFiles::Apache;    # using Cpanel::LoadModule w/ add 450 to RSS which deviates from the intent of this being a lightweight way to know where all the config files are
    my $apache_mime = Cpanel::ConfigFiles::Apache::apache_paths_facade()->file_conf_mime_types();
    return $apache_mime;
}

sub find_srmconf {
    my $apache_srm = get_srmconf();

    #CANNOT use wantarray here
    my ( @LOC, $loc );
    if ( -e $apache2_marker ) {
        @LOC = ( $apache2_srm, $default_srm );
    }
    else {
        @LOC = ( $apache_srm, $default_srm );
    }
    foreach $loc (@LOC) {
        if ( -e $loc ) {
            return $loc;
        }
    }
    return;
}

sub find_mimetypes {
    my $apache_mime = get_mimetypes();

    #CANNOT use wantarray here
    my ( @LOC, $loc );
    if ( -e $apache2_marker ) {
        @LOC = ( $apache2_mime, $default_mime );
    }
    else {
        @LOC = ( $apache_mime, $default_mime );
    }
    foreach $loc (@LOC) {
        if ( -e $loc ) {
            return $loc;
        }
    }
    return;
}

sub stat_mimetypes {
    my $file = find_mimetypes();
    my @stat = stat(_);
    return wantarray ? ( $file, \@stat ) : $file;
}

1;
