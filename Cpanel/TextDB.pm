package Cpanel::TextDB;

# cpanel - Cpanel/TextDB.pm                        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::SafeFile        ();
use Cpanel::Binaries        ();
use Cpanel::SafeRun::Simple ();
use Cpanel::Debug           ();
use Cpanel::ConfigFiles     ();

our $VERSION = '2.2';

my %NEEDS_DB = (
    '/etc/userdomains'                                       => 1,
    '/etc/trueuserdomains'                                   => 1,
    '/etc/trueuserowners'                                    => 1,
    '/etc/demouids'                                          => 1,
    '/etc/demousers'                                         => 1,
    $Cpanel::ConfigFiles::OUTGOING_MAIL_SUSPENDED_USERS_FILE => 1,
    $Cpanel::ConfigFiles::OUTGOING_MAIL_HOLD_USERS_FILE      => 1,
    '/etc/demodomains'                                       => 1,
    '/etc/domainusers'                                       => 1,
    '/etc/localdomains'                                      => 1,
    '/etc/remotedomains'                                     => 1,
    '/etc/secondarymx'                                       => 1,
    '/etc/userplans'                                         => 1,
    '/etc/userbwlimits'                                      => 1
);

sub addline {
    my ( $line, $file ) = @_;

    # builddb should probably be set to 1 ( but this will change the previous behaviour )
    return _update_file( 'add' => 1, file => $file, 'keys' => [$line], separator => '', builddb => 0, order => 'first' );
}

sub addentry {
    _update_file( 'add' => 1, @_ );
}

sub rementry {
    _update_file( 'delete' => 1, @_ );
}

sub _check_file {
    my $file = shift;

    return unless $file;
    $file = '/etc/' . $file if ( $file !~ /^\// );

    if ( !-e $file ) {
        Cpanel::Debug::log_warn("Could not find $file");
        return;
    }

    return $file;
}

sub _update_file {
    my %OPTS = @_;

    return unless $OPTS{'keys'} && ref $OPTS{'keys'} eq 'ARRAY';

    # by default try to rebuildb if file is listed
    $OPTS{'builddb'} = 1 unless defined( $OPTS{'builddb'} );

    my $separator = defined $OPTS{'separator'} ? $OPTS{'separator'} : ': ';
    my $line      = join( $separator, @{ $OPTS{'keys'} } );
    chomp($line);
    $line =~ s/\n//g;

    my $file = _check_file( $OPTS{'file'} );
    return unless $file;

    my $filelock = Cpanel::SafeFile::safeopen( \*ADDLINEFH, '+<', $file );
    if ( !$filelock ) {
        Cpanel::Debug::log_warn("Could not edit $file");
        return;
    }
    my @CF = <ADDLINEFH>;

    # get file header
    my @HEADER;
    while ( defined $CF[0] && $CF[0] =~ /^#/ ) {
        push @HEADER, shift @CF;
    }
    seek( ADDLINEFH, 0, 0 );
    print ADDLINEFH join( '', @HEADER );

    # keep only other lines
    @CF = grep( $_ !~ /^\Q$line\E$/, @CF ) if $OPTS{'delete'};
    if ( $OPTS{'add'} ) {
        if ( $OPTS{'order'} && $OPTS{'order'} eq 'first' ) {
            unshift( @CF, "$line\n" );
        }
        else {

            # fix missing newline
            push( @CF, "\n" ) if scalar @CF && $CF[-1] && $CF[-1] !~ /\n$/;
            push( @CF, "$line\n" );
        }
    }
    print ADDLINEFH join( '', @CF );
    truncate( ADDLINEFH, tell(ADDLINEFH) );

    if ( $NEEDS_DB{$file} && $OPTS{'builddb'} ) {
        _builddb($file);
    }

    return Cpanel::SafeFile::safeclose( \*ADDLINEFH, $filelock );
}

sub _builddb {
    my $file          = shift;
    my $exim_dbmbuild = Cpanel::Binaries::path('exim_dbmbuild');
    return Cpanel::SafeRun::Simple::saferun( $exim_dbmbuild, $file, $file . '.db' );
}
1;
