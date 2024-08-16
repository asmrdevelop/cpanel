package Cpanel::Passwd::Shell;

# cpanel - Cpanel/Passwd/Shell.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

our $VERSION = 1.0;

use AcctLock                       ();
use Cpanel::Transaction::File::Raw ();
use Cpanel::NSCD                   ();
use Cpanel::SSSD                   ();
use Cpanel::Exception              ();
use Try::Tiny;

our $PASSWD_PERMS = 0644;
our $PASSWD_FILE  = '/etc/passwd';

sub update_shell {
    my (%opts) = @_;

    AcctLock::acctlock();

    try {
        update_shell_without_acctlock(%opts);
    }
    catch {
        local $@ = $_;
        die;
    }
    finally {
        Cpanel::NSCD::clear_cache();
        Cpanel::SSSD::clear_cache();
        AcctLock::acctunlock();
    };

    return 1;
}

sub update_shell_without_acctlock {
    my (%opts) = @_;

    my ( $user, $shell ) = @opts{qw(user shell)};

    die Cpanel::Exception::create( 'MissingParameter', [ name => 'user' ] )  if !length $user;
    die Cpanel::Exception::create( 'MissingParameter', [ name => 'shell' ] ) if !length $shell;

    if ( $shell !~ m/^[A-Za-z0-9\.\/=\_]+$/ ) {
        die Cpanel::Exception::create( 'InvalidCharacters', 'The shell name may only contain the following characters: [join, ,_1]', [qw( a-z A-Z 0-9 \. \/ = \_ )] );
    }
    if ( $user eq 'root' ) {

        # Implementor error
        die Cpanel::Exception::create( 'InvalidUsername', [ value => 'root' ] );
    }

    my $trans   = Cpanel::Transaction::File::Raw->new( 'path' => $PASSWD_FILE, 'permissions' => $PASSWD_PERMS );
    my $dataref = $trans->get_data();

    my $seenline = 0;
    my @passwd;

    my $user_line_start = "$user:";

    foreach my $line ( split( m{\n}, $$dataref ) ) {
        if ( $user_line_start eq substr( $line, 0, length $user_line_start ) ) {
            my @LINE = split( m/:/, $line );
            $LINE[6] = $shell;

            #
            # This cleans up the line since some of our
            # older tools leave missing fields.
            #
            # The fields must be filled or system tools will error
            #
            for ( 0 .. 6 ) { $LINE[$_] ||= ''; }
            $line     = join( ':', @LINE );
            $seenline = 1;
        }
        push @passwd, $line;
    }

    if ( !$seenline ) {
        $trans->abort();
        die Cpanel::Exception::create( 'InvalidUsername', [ value => $user ] );
    }

    $$dataref = join( "\n", @passwd ) . "\n";

    $trans->save_and_close_or_die();
    return 1;

}

1;
