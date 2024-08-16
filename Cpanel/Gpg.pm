package Cpanel::Gpg;

# cpanel - Cpanel/Gpg.pm                           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use Cpanel                     ();
use Cpanel::Locale             ();
use Cpanel::SafeRun::Errors    ();
use Cpanel::CryptGPG           ();
use Cpanel::Binaries           ();
use Cpanel::Validate::EmailRFC ();
require Exporter;

our ( @ISA, @EXPORT, $VERSION );
@ISA     = qw(Exporter);
@EXPORT  = qw(genkey listsecretgpgkeys listgpgkeys importkeys exportsecretkey exportkey deletekey);
$VERSION = '1.4';

sub find_gpg {
    my $bin = Cpanel::Binaries::path('gpg');
    if ( -x $bin ) {
        return $bin;
    }
    return;
}

sub genkey {    ## no critic qw(ProhibitManyArgs)
    my ( $name, $comment, $email, $expire, $keysize, $passphrase ) = @_;
    my $locale = Cpanel::Locale->get_handle();
    if ( !main::hasfeature('pgp') ) {
        $Cpanel::CPERROR{'gpg'} = $locale->maketext('Sorry, permission denied. This feature is not enabled.');
        print $Cpanel::CPERROR{'gpg'};
        return;
    }
    if ( $Cpanel::CPDATA{'DEMO'} eq '1' ) {
        $Cpanel::CPERROR{'gpg'} = $locale->maketext('Sorry, this feature is disabled in demo mode.');
        print $Cpanel::CPERROR{'gpg'};
        return;
    }

    my $gpg_bin = find_gpg();
    if ( !$gpg_bin ) {
        $Cpanel::CPERROR{'gpg'} = $locale->maketext('Sorry, unable to locate system support for this feature.');
        print $Cpanel::CPERROR{'gpg'};
        return;
    }

    if ( length $name < 5 ) {
        $Cpanel::CPERROR{'gpg'} = $locale->maketext('Sorry, the name field must be at least 5 characters.');
        print $Cpanel::CPERROR{'gpg'};
        return;
    }

    my $passphrase_line;

    #NOTE: The --passphrase-fd appears not to work for key generation;
    #otherwise we could support leading/trailing spaces.
    #
    if ( length $passphrase ) {
        if ( $passphrase =~ m<\A\s|\s\z> ) {
            $Cpanel::CPERROR{'gpg'} = $locale->maketext('The passphrase may not begin or end with a space.');
            print $Cpanel::CPERROR{'gpg'};
            return;
        }

        $passphrase_line = "Passphrase: $passphrase";
    }
    else {

        #NOTE: There used to be logic here that did:
        #
        #$passphrase = '""'
        #
        #...but that didn't actually work.
        #
        #Per the below:
        #https://www.gnupg.org/documentation/manuals/gnupg/Unattended-GPG-key-generation.html
        #
        #...gpg doesn't actually understand a quoted string.

        $passphrase_line = q<>;
    }

    if ( !Cpanel::Validate::EmailRFC::is_valid($email) ) {
        $Cpanel::CPERROR{'gpg'} = $locale->maketext('Sorry, the supplied email address is not valid.');
        print $Cpanel::CPERROR{'gpg'};
        return;
    }

    # Normalize to 1024, 2048, 3072 or 4096
    if ( $keysize <= 1024 ) {
        $keysize = 1024;
    }
    elsif ( $keysize <= 2048 ) {
        $keysize = 2048;
    }
    elsif ( $keysize <= 3072 ) {
        $keysize = 3072;
    }
    else {
        $keysize = 4096;
    }

    # Normalize expire to days, default to 1y
    if ( !$expire ) {
        $expire = 0;    # 0 is valid, never expires
    }
    elsif ( $expire !~ m/^\d+[ymwd]/ ) {
        $expire = '1y';
    }

    unlink "$Cpanel::homedir/.gpgtemp";
    if ( open my $gpgtmp_fh, '>', "$Cpanel::homedir/.gpgtemp" ) {
        chmod 0600, "$Cpanel::homedir/.gpgtemp";
        print {$gpgtmp_fh} <<"EOM";
   \%echo Generating a standard key
   Key-Type: RSA
   Key-Length: $keysize
   Subkey-Type: RSA
   Subkey-Length: $keysize
   Name-Real: $name
   Name-Comment: $comment
   Name-Email: $email
   Expire-Date: $expire
#1w 1day etc
$passphrase_line
# Do a commit here, so that we can later print "done" :-)
\%commit
\%echo done
EOM
        close $gpgtmp_fh;
    }
    Cpanel::SafeRun::Errors::saferunnoerror( $gpg_bin, '--no-secmem-warning', '--batch', '--list-keys' );
    print Cpanel::SafeRun::Errors::saferunnoerror( $gpg_bin, '--no-secmem-warning', '-v', '--batch', '--gen-key', '-a', "$Cpanel::homedir/.gpgtemp" );
    unlink "$Cpanel::homedir/.gpgtemp";
    return 1;
}

sub deletekey {
    my ( $id, $secret ) = @_;
    my $locale = Cpanel::Locale->get_handle();
    if ( !main::hasfeature('pgp') ) {
        $Cpanel::CPERROR{'gpg'} = $locale->maketext('Sorry, permission denied. This feature is not enabled.');
        print $Cpanel::CPERROR{'gpg'};
        return;
    }
    if ( $Cpanel::CPDATA{'DEMO'} eq '1' ) {
        $Cpanel::CPERROR{'gpg'} = $locale->maketext('Sorry, this feature is disabled in demo mode.');
        print $Cpanel::CPERROR{'gpg'};
        return;
    }
    if ( !$id ) {
        $Cpanel::CPERROR{'gpg'} = $locale->maketext('No key specified');
        print $Cpanel::CPERROR{'gpg'};
        return;
    }

    my $gpg_bin = find_gpg();
    if ( !$gpg_bin ) {
        $Cpanel::CPERROR{'gpg'} = $locale->maketext('Sorry, unable to locate system support for this feature.');
        print $Cpanel::CPERROR{'gpg'};
        return;
    }

    my $gpg = Cpanel::CryptGPG->new;

    #$gpg->{'GPGBIN'} = $gpg_bin;

    my @keys = $gpg->keydb( ($id) );

    my $delete_key;
    my $has_secret = 0;
    foreach my $key (@keys) {
        if ($secret) {
            if ( $key->{'Type'} eq 'sec' ) {
                $delete_key = $key;
                last;
            }
        }
        elsif ( $key->{'Type'} eq 'sec' ) {
            $has_secret = 1;
        }
        elsif ( $key->{'Type'} eq 'pub' ) {
            $delete_key = $key;
        }
    }

    if ( !$delete_key ) {
        $Cpanel::CPERROR{'gpg'} = $locale->maketext( "Sorry, could not locate a key for ID \xE2\x80\x9C[_1]\xE2\x80\x9D.", $id );
        print $Cpanel::CPERROR{'gpg'};
        return;
    }
    elsif ($has_secret) {
        $Cpanel::CPERROR{'gpg'} = $locale->maketext('Sorry, you must delete the secret key before removing the public key.');
        print $Cpanel::CPERROR{'gpg'};
        return;
    }

    if ( $gpg->delkey($delete_key) ) {
        return $locale->maketext( "Deleted key \xE2\x80\x9C[_1]\xE2\x80\x9D", $id );
    }
    else {
        $Cpanel::CPERROR{'gpg'} = $locale->maketext( "Sorry, deletion of key \xE2\x80\x9C[_1]\xE2\x80\x9D failed.", $id );
        print $Cpanel::CPERROR{'gpg'};
        return;
    }
    return $locale->maketext('Failed to delete key');
}

sub exportkey {
    my ($key) = @_;
    my $locale = Cpanel::Locale->get_handle();
    if ( !main::hasfeature('pgp') ) {
        $Cpanel::CPERROR{'gpg'} = $locale->maketext('Sorry, permission denied. This feature is not enabled.');
        print $Cpanel::CPERROR{'gpg'};
        return;
    }
    if ( $Cpanel::CPDATA{'DEMO'} eq '1' ) {
        $Cpanel::CPERROR{'gpg'} = $locale->maketext('Sorry, this feature is disabled in demo mode.');
        print $Cpanel::CPERROR{'gpg'};
        return;
    }

    if ( !$key ) {
        $Cpanel::CPERROR{'gpg'} = $locale->maketext('No key specified');
        print $Cpanel::CPERROR{'gpg'};
        return;
    }

    my $gpg_bin = find_gpg();
    if ( !$gpg_bin ) {
        $Cpanel::CPERROR{'gpg'} = $locale->maketext('Sorry, unable to locate system support for this feature.');
        print $Cpanel::CPERROR{'gpg'};
        return;
    }

    open( GPG, '-|' ) || exec( $gpg_bin, '--no-secmem-warning', '-a', '--export', $key );
    while (<GPG>) {
        print;
    }
    close(GPG);
    return;
}

sub exportsecretkey {
    my ($key) = @_;

    my $locale = Cpanel::Locale->get_handle();
    if ( !main::hasfeature('pgp') ) {
        $Cpanel::CPERROR{'gpg'} = $locale->maketext('Sorry, permission denied. This feature is not enabled.');
        print $Cpanel::CPERROR{'gpg'};
        return;
    }
    if ( $Cpanel::CPDATA{'DEMO'} eq '1' ) {
        $Cpanel::CPERROR{'gpg'} = $locale->maketext('Sorry, this feature is disabled in demo mode.');
        print $Cpanel::CPERROR{'gpg'};
        return;
    }
    if ( !$key ) {
        $Cpanel::CPERROR{'gpg'} = $locale->maketext('No key specified');
        print $Cpanel::CPERROR{'gpg'};
        return;
    }

    my $gpg_bin = find_gpg();
    if ( !$gpg_bin ) {
        $Cpanel::CPERROR{'gpg'} = $locale->maketext('Sorry, unable to locate system support for this feature.');
        print $Cpanel::CPERROR{'gpg'};
        return;
    }

    open( GPG, '-|' ) || exec( $gpg_bin, '--no-secmem-warning', '-a', '--export-secret-key', $key );
    while (<GPG>) {
        print;
    }
    close(GPG);
    return;
}

sub importkeys {
    my ($keydata) = @_;

    my $locale = Cpanel::Locale->get_handle();
    if ( !main::hasfeature('pgp') ) {
        $Cpanel::CPERROR{'gpg'} = $locale->maketext('Sorry, permission denied. This feature is not enabled.');
        print $Cpanel::CPERROR{'gpg'};
        return;
    }
    if ( $Cpanel::CPDATA{'DEMO'} eq '1' ) {
        $Cpanel::CPERROR{'gpg'} = $locale->maketext('Sorry, this feature is disabled in demo mode.');
        print $Cpanel::CPERROR{'gpg'};
        return;
    }

    if ( !$keydata ) {
        $Cpanel::CPERROR{'gpg'} = $locale->maketext('No key specified');
        print $Cpanel::CPERROR{'gpg'};
        return;
    }

    my $gpg_bin = find_gpg();
    if ( !$gpg_bin ) {
        $Cpanel::CPERROR{'gpg'} = $locale->maketext('Sorry, unable to locate system support for this feature.');
        print $Cpanel::CPERROR{'gpg'};
        return;
    }

    open( GPGW, '|-' ) || exec( $gpg_bin, '--no-secmem-warning', '--import' );
    print GPGW $keydata . \0;
    close(GPGW);
    return;
}

# sets the CPVAR{'gpg_number_of_private_keys'} and returns the value
sub api2_number_of_private_keys {
    my @KEYS = _listgpgkeys('sec');
    $Cpanel::CPVAR{'gpg_number_of_private_keys'} = scalar @KEYS;
    return ( { 'count' => scalar @KEYS } );
}

# sets the CPVAR{'gpg_number_of_public_keys'} and returns the value
sub api2_number_of_public_keys {
    my @KEYS = _listgpgkeys('pub');
    $Cpanel::CPVAR{'gpg_number_of_public_keys'} = scalar @KEYS;
    return ( { 'count' => scalar @KEYS } );
}

sub api2_listsecretgpgkeys {
    return ( _listgpgkeys('sec') );
}

sub api2_listgpgkeys {
    return ( _listgpgkeys('pub') );
}

sub listsecretgpgkeys {
    my @GC = _listgpgkeys('sec');
    my @G;
    foreach my $g (@GC) {
        push( @G, "$$g{'id'} $$g{'name'} $$g{'email'}" );
    }
    return @G;
}

sub listgpgkeys {
    my @GC = _listgpgkeys('pub');
    my @G;
    foreach my $g (@GC) {
        push( @G, "$$g{'id'} $$g{'name'} $$g{'email'}" );
    }
    return @G;
}

sub _listgpgkeys {    ## no critic(Subroutines::ProhibitExcessComplexity)  -- Refactoring this function is a project, not a bug fix
    my ($keytype) = @_;
    my $locale = Cpanel::Locale->get_handle();
    if ( !main::hasfeature('pgp') ) {
        $Cpanel::CPERROR{'gpg'} = $locale->maketext('Sorry, permission denied. This feature is not enabled.');
        return;
    }

    my $gpg_bin = find_gpg();
    if ( !$gpg_bin ) {
        $Cpanel::CPERROR{'gpg'} = $locale->maketext('Sorry, unable to locate system support for this feature.');
        return;
    }

    # Run gpg three times to initialize then return nothing
    if ( !-d $Cpanel::homedir . '/.gnupg' ) {
        for ( 1 .. 3 ) {
            Cpanel::SafeRun::Errors::saferunallerrors( $gpg_bin, '--no-secmem-warning', '--batch', '--list-keys' );
        }
        return;
    }

    if ( $keytype eq 'pub' ) {
        open( GPG, "$gpg_bin --no-secmem-warning --batch --list-keys 2>/dev/null |" );
    }
    else {
        open( GPG, "$gpg_bin --no-secmem-warning --batch --list-secret-keys 2>/dev/null |" );
    }

    my $debug = 0;
    my @RKEYS;
    my ( $type, $bits, $id, $maintype, $name, $email, $comment, $date );
    my $_reset_loop_vars = sub {
        $type     = '';
        $bits     = '';
        $id       = '';
        $name     = '';
        $email    = '';
        $comment  = '';
        $maintype = '';
    };
    my $_check_loop_vars = sub {
        print "_check_loop_vars currently has: type($type) bits($bits) id($id) name($name)\n" if $debug;
        return 1                                                                              if ( $type && $bits && $id && $name );
        return;
    };
    my $_add_loop_vars = sub {
        if ( $_check_loop_vars->() ) {
            push @RKEYS,
              {
                'name'  => $name,
                'date'  => $date,
                'email' => $email,
                'bits'  => $bits,
                'id'    => $id,
                'keyid' => $id,
                'type'  => $maintype,
                'key'   => "$id [$bits] $name" . ( $email ? " ($email)" : '' ),
              };
            $_reset_loop_vars->();
            return 1;
        }
        else {
            $_reset_loop_vars->();
            return;
        }
    };
    my $id_regex    = qr/[A-H0-9]+/;
    my $blank_regex = qr/^\s*$/;
    my $type_regex  = qr/[pubsidec]{3}/xmsi;
    my $date_regex  = qr/[0-9]{4}-[0-9]{2}-[0-9]{2}/xms;
    my $email_regex = qr/\s+ <(\S+@\S+)> (?:\s+|\z)/xms;

    $_reset_loop_vars->();
    my $skipentry = 0;
  GPGLOOP:
    while ( my $line = <GPG> ) {
        chomp;
        print "\n### Current line($line)\n### type($type) bits($bits) id($id) name($name)\n" if $debug;
        if ( $line =~ $blank_regex ) {
            print "End entry\n" if $debug;
            $_add_loop_vars->();    # don't check return ??
            $skipentry = 0;
            next GPGLOOP;
        }
        if ( $line =~ m/\A\s+($id_regex) \s+/xmsi ) {
            $id = $1;
            print "Line matched ID ($id)\n" if $debug;
            $skipentry = 0;
            next GPGLOOP;
        }
        if ( $line =~ m/\A ($type_regex) \s+/xmsi ) {
            $type = lc $1;
            if ( !$maintype ) {
                $maintype = $type;
            }
            print "Line type: $type\n" if $debug;

            if ( $type eq 'pub' || $type eq 'sec' ) {

                # Get bits, id and date
                if ( $line =~ m/\A $type_regex \s+ (\S+) \s+ ($date_regex) \s+/xmsi ) {
                    my $bitsid = $1;
                    $date = $2;
                    print "Date: $date\n"      if $debug;
                    print "Bits/ID: $bitsid\n" if $debug;
                    if ( $bitsid =~ m/\// ) {
                        ( $bits, $id ) = split /\//, $bitsid, 2;
                    }
                    else {
                        # we'll hope to get the id on the next line
                        $bits = $bitsid;
                    }
                    if ( !$bits || !$date ) {
                        warn "Unable to determine key info (bits and date)." if $debug;
                        $skipentry = 1;
                        next GPGLOOP;
                    }
                    else {

                        # check old format for name and email
                        if ( $line =~ $email_regex ) {
                            if ($email) {
                                $email .= ', ' . $1;
                            }
                            else {
                                $email = $1;
                            }
                            print "Email: $email\n" if $debug;
                            if ( $line =~ m/$date_regex \s+ (\S+[\s\S]+\S+) $email_regex/xms ) {
                                if ($name) {
                                    $name .= ', ' . $1;
                                }
                                else {
                                    $name = $1;
                                }
                                print "Name: $name\n" if $debug;
                            }
                            else {
                                print "No name: $line\n" if $debug;
                            }
                        }
                        else {
                            print "No email: $line\n" if $debug;
                        }

                    }

                }
                else {
                    warn "Unable to determine bits and id." if $debug;
                    $skipentry = 1;
                    next GPGLOOP;
                }
            }
            elsif ( $type eq 'uid' ) {

                # Get name and email
                if ( $line =~ $email_regex ) {
                    if ($email) {
                        $email .= ', ' . $1;
                    }
                    else {
                        $email = $1;
                    }
                    print "Email: $email\n" if $debug;

                    # Now get name
                    if ( $line =~ m/\A $type_regex \s+ (\S+[\s\S]+\S+) $email_regex/xmsi ) {
                        if ($name) {
                            $name .= ', ' . $1;
                        }
                        else {
                            $name = $1;
                        }
                        print "Name: $name\n" if $debug;
                    }
                    else {
                        print "No name: $line\n" if $debug;
                    }
                }
                else {
                    print "No email: $line\n" if $debug;
                    if ( $line =~ m/\A $type_regex \s+ (\S+.*?) \s* \Z/xmsi ) {
                        $name = $1;
                        print "Name: $name\n" if $debug;
                    }
                    else {
                        print "No name: $line\n" if $debug;
                    }
                }
            }
            else {
                print "Skipping $line\n" if $debug;
            }
        }
        else {
            warn "Shouldn't get here." if $debug;
        }
    }
    close(GPG);

    return @RKEYS;
}

my $pgp_feature = {
    needs_role    => "MailReceive",
    needs_feature => "pgp",
    allow_demo    => 1,
};

our %API = (
    listsecretgpgkeys      => $pgp_feature,
    listgpgkeys            => $pgp_feature,
    number_of_private_keys => $pgp_feature,
    number_of_public_keys  => $pgp_feature,
);

sub api2 {
    my ($func) = @_;
    return { %{ $API{$func} } } if $API{$func};
    return;
}

1;
