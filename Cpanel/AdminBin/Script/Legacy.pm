package Cpanel::AdminBin::Script::Legacy;

# cpanel - Cpanel/AdminBin/Script/Legacy.pm        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#----------------------------------------------------------------------
#NOTE: Consider using Cpanel::AdminBin::Script::Call instead of this class.
#----------------------------------------------------------------------

use strict;
## no critic qw(RequireUseWarnings) # TODO: Make this use warnings

use Cpanel::AdminBin::Serializer ();
use Cpanel::AdminBin::Utils      ();
use Cpanel::PwCache              ();
use Cpanel::Logger               ();
use Cpanel::Locale               ();
use Cpanel                       ();
use Cpanel::ConfigFiles          ();
use Cpanel::Reseller             ();

sub run_adminbin {
    my ( $class, $commands, %opts ) = @_;

    local $@;
    my ( $status, $message, $action ) = eval { __PACKAGE__->script( $commands, @ARGV ) };

    if ($@) {
        print "$@\n";
        return 1;
    }

    if ( !defined $message ) {
        print "Invalid message returned.\n";
        return 1;
    }

    my $message_ref_type = ref $message;
    my $dump_message;
    if ($message_ref_type) {

        # force to dump the array when the array contains a structure ( EXPORT )
        #   or when the user ask for it
        $dump_message = 1 if $message_ref_type eq 'ARRAY' && ( grep( { ref $_ } @$message ) || $opts{dump_array} );
        $dump_message = 1 if $message_ref_type eq 'HASH';
    }

    if ( !$message_ref_type ) {
        print $message;
        print "\n" unless $opts{no_newline};
    }
    elsif ( !$dump_message && $message_ref_type eq 'ARRAY' ) {
        for my $message_part ( @{$message} ) {
            print $message_part . "\n";
        }
    }
    elsif ($dump_message) {
        print "." . "\n";
        print Cpanel::AdminBin::Serializer::Dump($message);
    }
    else {
        print "Invalid message returned.\n";
        return 1;
    }

    if ( !$status ) {
        return (5);    #Errno::EIO
    }

    return 0;
}

{
    my $logger;

    sub logger {
        $logger ||= Cpanel::Logger->new();
        return $logger;
    }
}

sub script {
    my ( $class, $commands, @argv ) = @_;

    alarm(500);

    foreach (qw/TERM PIPE USR1 USR2 HUP/) {
        $SIG{$_} = 'IGNORE';
    }

    my ( $status, $uid, $action, @args ) = Cpanel::AdminBin::Utils::get_command_line_arguments(@argv);

    if ( !$action || !exists $commands->{$action} ) {
        logger()->warn( 'no valid action:' . ( $action || '(none)' ) );
        return ( 0, "no valid action" );
    }

    my ( $user, $gid, $home_directory ) = ( Cpanel::PwCache::getpwuid( int($uid) ) )[ 0, 3, 7 ];

## valid users: 'cpanel' or existing user
    ## invalid: 'root' or non-existing user
    if ( $user ne 'cpanel' && ( !$user || $user eq 'root' || !-e "$Cpanel::ConfigFiles::cpanel_users/$user" ) ) {
        logger()->warn('invalid user');
        return ( 0, "Invalid user: $user" );
    }

    # SECURITY :: IT IS NOW VERY IMPORTANT THAT $user BE CORRECT
    $ENV{'REMOTE_USER'} = $user;    # Cpanel::SSLInstall requires this to be correct
                                    # or it will give the user privs to overwrite
                                    # certs (is has_root())

    # SECURITY :: IT IS NOW VERY IMPORTANT THAT $user BE CORRECT

    Cpanel::initcp($user);

    my $dns = $Cpanel::CPDATA{'DNS'};
    if ( !$dns && !Cpanel::Reseller::isreseller($user) ) {
        logger()->warn('Uninitialized Cpanel::CPDATA, not a reseller account and no DNS has been specified.');
        my $locale = Cpanel::Locale->get_handle();
        return ( 0, $locale->maketext('Your [asis,cPanel] Config file is missing [output,acronym,DNS,Domain Name System] info.') );
    }

    return ( ( $commands->{$action}->( $user, $action, @args ) ), $action );
}

1;
