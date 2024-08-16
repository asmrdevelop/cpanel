package Cpanel::SSH;

# cpanel - Cpanel/SSH.pm                           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Cpanel::Imports;

use Cpanel                        ();    # for CPERROR
use Cpanel::PwCache               ();
use Cpanel::LoadModule            ();
use Cpanel::LoadFile              ();
use Cpanel::Locale                ();
use Cpanel::FileUtils::Move       ();
use Cpanel::FileUtils::Write      ();
use Cpanel::FileUtils::TouchFile  ();
use Cpanel::JSON                  ();
use Cpanel::Logger                ();
use Cpanel::PasswdStrength::Check ();
use Cpanel::PwCache               ();
use Cpanel::Rand                  ();
use Cpanel::SSH::Port             ();
use Cpanel::SafeFile              ();
use Cpanel::SafeRun::Full         ();
use Cpanel::Sort                  ();
use Cpanel::StringFunc::Trim      ();
use Whostmgr::ACLS                ();
use MIME::Base64                  ();
use Cpanel::Binaries              ();

our $SSH_KEY_OPERATION_TIMEOUT = 500;    #case 148373: This can take a while if the load is high

#-----global regexes should all work in javascript as well as perl
my $_BASE64_CHAR = '[a-zA-Z0-9/+=]';

#the backslash before the opening bracket is necessary for perl 5.6 (case 39369)
my $_BASE64_CHAR_SPACES = "${_BASE64_CHAR}\[a-zA-Z0-9/+=\\s]+$_BASE64_CHAR";

my $_AUTHORIZED_COMMAND_REGEX = '(.*\S)?';

our $PUBLIC_SSH2_KEY_REGEX = '(ssh-(?:rsa|dss|ed25519)|ecdsa-sha2-nistp(?:256|384|521))\s+(' . $_BASE64_CHAR . '+)\s*(\S.*)?';
my $_AUTHORIZED_SSH2_KEY_REGEX = $_AUTHORIZED_COMMAND_REGEX . '\s*' . $PUBLIC_SSH2_KEY_REGEX;

our $PRIVATE_SSH2_KEY_REGEX = '-----BEGIN (RSA|DSA|EC|OPENSSH) PRIVATE KEY-----[\r\n]+'    #1: algorithm
  . '\s*' . '((?:.*\s*:\s*.*[\r\n]+)*)'                                                    #2: metadata; the colon is critical
  . '\s*' . "($_BASE64_CHAR_SPACES)" . '[\r\n]+'                                           #3: base64
  . '\s*' . '-----END \1 PRIVATE KEY-----';

our $PUTTY_SSH2_KEY_REGEX = 'PuTTY-User-Key-File-2:\s+([^\r\n]+)[\r\n]+'                   #1: algorithm
  . 'Encryption:\s+([^\r\n]+)[\r\n]+'                                                      #2: encryption
  . 'Comment:\s+([^\r\n]+)[\r\n]+'                                                         #3: comment
  . 'Public-Lines:[^\r\n]+[\r\n]+' . "($_BASE64_CHAR_SPACES)" . '[\r\n]+'                  #4: public base64
  . 'Private-Lines:[^\r\n]+[\r\n]+' . "($_BASE64_CHAR_SPACES)" . '[\r\n]+'                 #5: private base64
  . 'Private-MAC:\s+([^\r\n]+)'                                                            #6: private MAC
  ;

our $PUBLIC_RSA1_KEY_REGEX = '(\d+)\s+(\d+)\s+(\d+)\s*(\S.*)?';
my $_AUTHORIZED_RSA1_KEY_REGEX = $_AUTHORIZED_COMMAND_REGEX . '\s*' . $PUBLIC_RSA1_KEY_REGEX;
our $_PRIVATE_RSA1_KEY_REGEX = 'SSH PRIVATE KEY FILE FORMAT 1.1\n.*';

#exclude empty string, leading period, space, and foreslash
#NOTE: This string gets sent to JavaScript, so filename validation needs
#not to be more complex than a single regular expression.
our $INVALID_FILENAME_REGEX = '(^$|^\.|[\s/\0])';

#------

#authorized_keys2 is deprecated
my @_AUTHORIZED_KEYS_FILES = qw( authorized_keys2 authorized_keys );
my $_DEPRECATED_KEY_FILE   = 'authorized_keys2';

my %_RESERVED_KEY_NAMES_LOOKUP = (
    ( map { $_ => 1 } @_AUTHORIZED_KEYS_FILES ),
    'config'      => 1,
    'environment' => 1,
    'identity'    => 1,
    'known_hosts' => 1,
    'rc'          => 1,
);

my %_VALID_ALGORITHMS_LOOKUP = (
    'rsa2' => 1,
    'dsa'  => 1,
);
my $_DEFAULT_ALGORITHM = 'rsa2';

my $logger = Cpanel::Logger->new();

*_getport = *Cpanel::SSH::Port::getport;

## DEPRECATED!
sub SSH_getport {
    ## no args
    require Cpanel::API;
    my $result = Cpanel::API::_execute( "SSH", "get_port" );
    return print $result->data()->{'port'};
}

sub api2_converttoppk {
    my %OPTS = @_;
    my $name = $OPTS{'name'} || '';
    $name =~ s/\///g;
    $name =~ s/\.\.//g;

    $OPTS{'file'} = $name;
    delete $OPTS{'name'};
    $OPTS{'passphrase'} ||= $OPTS{'pass'};

    if ( !exists $OPTS{'keep_file'} ) {
        $OPTS{'keep_file'} = 1;
    }

    my $key = _converttoppk(%OPTS);

    my @RSD;
    push( @RSD, { 'key' => $key, 'name' => $name, 'result' => ( $key ne '' ? 1 : 0 ) } );
    return @RSD;
}

#This could, theoretically, be done manually in Perl without puttygen,
#but we would have to decrypt.
#The public key part of a PuTTY key is just the Base64 of the regular one
#   (i.e. descriptor, public exponent, modulus).
#The private part is Base64 of:
#   private exponent, prime 1, prime 2, coefficient.
#The MAC is described at http://www.thule.no/~troels/code/pem2putty.c
sub _converttoppk {

    my %OPTS = @_;

    if ( !main::hasfeature('ssh') ) {
        $Cpanel::CPERROR{'ssh'} = 'This feature is not enabled';
        return;
    }

    if ( $Cpanel::CPDATA{'DEMO'} ) {
        my $locale = Cpanel::Locale->get_handle();
        $Cpanel::CPERROR{'ssh'} = $locale->maketext('Sorry, this feature is disabled in demo mode.');
        return;
    }

    my $user = _get_user( $OPTS{'user'} );
    return if !$user;

    my $sshdir = _getsshdir($user);
    return if !$sshdir;

    my $file = $OPTS{'file'};
    return if !_filename_is_valid($file);
    if ( !-r $sshdir . '/' . $file ) {
        $Cpanel::CPERROR{'ssh'} = 'Unable to read selected key file.';
        return;
    }

    my $pgen = Cpanel::Binaries::path('puttygen');
    if ( !-x $pgen ) {
        $Cpanel::CPERROR{'ssh'} = $pgen . ' is missing or not executable. To get the needed package, you should be able to run /usr/local/cpanel/scripts/check_cpanel_pkgs --targets=3rdparty --fix';
        return;
    }

    my $ppk_file = Cpanel::Rand::gettmpfile();    # audit case 46806 ok

    my $orig_sigpipe_handler = $SIG{'PIPE'};
    local $SIG{'PIPE'}   = 'IGNORE';
    local $ENV{'LC_ALL'} = 'C';

    my $output_hr = Cpanel::SafeRun::Full::run(
        'program' => $pgen,
        'args'    => [
            $sshdir . '/' . $file,
            '-O' => 'private',
            '-o' => $ppk_file,
            '-X',
        ],
        'stdin'   => $OPTS{'passphrase'},
        'timeout' => $SSH_KEY_OPERATION_TIMEOUT,
    );

    $SIG{'PIPE'} = $orig_sigpipe_handler;

    my $ppk_text;
    my $unlink_temp = 1;
    if ( $output_hr->{'status'} ) {

        # Match this text exactly because we'll get it even if there's another error.
        if ( $output_hr->{'stderr'} && $output_hr->{'stderr'} ne "Enter passphrase to load key: \n" ) {
            $Cpanel::CPERROR{'ssh'} = $output_hr->{'stderr'};
        }
        elsif ( defined $output_hr->{'timeout'} ) {
            $Cpanel::CPERROR{'ssh'} = "Timeout while using puttygen to convert $file to ppk";
        }
        else {
            $ppk_text = Cpanel::LoadFile::loadfile($ppk_file);

            if ( $OPTS{'keep_file'} ) {
                my $puttydir = _getputtysshdir($user);

                if ($puttydir) {
                    my $permanent_ppk_file = "$puttydir/$file.ppk";
                    my $move               = Cpanel::FileUtils::Move::safemv( '-f', $ppk_file, $permanent_ppk_file );
                    if ($move) {
                        $unlink_temp = 0;
                    }
                    else {

                        #This isn't really an "error"; the function will still return the key text
                        $Cpanel::CPERROR{'ssh'} = "Error moving temp file to $permanent_ppk_file: $!";
                    }
                }
            }
        }
    }

    if ($unlink_temp) {
        unlink $ppk_file;
    }

    return $ppk_text || ();
}

sub api2_genkey {
    my %OPTS = @_;

    my $name = $OPTS{'name'} || q{};
    $name =~ tr{/ \t\r\n\f}{}d;
    $name =~ s{\.\.}{}g;
    $OPTS{'file'} = $name;

    my $key_path = _getsshdir( _get_user( $OPTS{'user'} ) ) . '/' . $name;
    my $now      = time();
    my $msg      = '';
    if ( -e $key_path ) {
        rename( $key_path, $key_path . '.' . $now );
        $msg .= "Backed up $key_path to $key_path.$now\n";
    }
    if ( -e $key_path . '.pub' ) {
        rename( $key_path . '.pub', $key_path . '.' . $now . '.pub' );
        $msg .= "Backed up $key_path.pub to $key_path.$now.pub\n";
    }

    $OPTS{'algorithm'} ||= delete $OPTS{'type'};
    if ( defined $OPTS{'algorithm'} && $OPTS{'algorithm'} ne 'dsa' ) {
        $OPTS{'algorithm'} = 'rsa2';
    }

    $OPTS{'passphrase'} ||= delete $OPTS{'pass'};

    # Case 157045 - do not allow invalid chars in name
    if ( length($name) && !( $name =~ m/^[0-9a-zA-Z\-_\.]+$/ ) ) {

        # we have an invalid character, maybe even because the UI html
        # encoded the value.
        my $reason = "Invalid Key Name";
        $Cpanel::CPERROR{'ssh'} = $reason;
        return { 'reason' => $reason, 'result' => 0, };
    }

    my ( $result, $warnings, $output ) = _genkey(%OPTS);

    my $reason = ref $output ? join( "\n", @{$output} ) : '';
    $reason = "$msg$reason";

    my $warning = ref $warnings ? join( "\n", @{$warnings} ) : '';

    return { 'reason' => $reason, 'result' => $result, length $warning ? ( 'warnings' => $warning ) : () };
}

#user (optional)
#passphrase (optional)
#name (optional, default id_rsa/id_dsa)
#bits (optional, default 4096, or 1024 for dsa)
#algorithm (optional)
#comment (optional)
#abort_on_existing_key(optional)
# NOTE: This function is used by the WHM json-api call generatesshkeypair.
# Be sure to test any modifications with the above api.
sub _genkey {    ## no critic qw(ProhibitExcessComplexity) -- legacy
    my %OPTS = @_;
    return if !main::hasfeature('ssh');

    if ( $Cpanel::CPDATA{'DEMO'} ) {
        my $locale = Cpanel::Locale->get_handle();
        $Cpanel::CPERROR{'ssh'} = $locale->maketext('Sorry, this feature is disabled in demo mode.');
        return;
    }

    #validate algorithm
    my $algorithm = $OPTS{'algorithm'};
    if ( defined $algorithm ) {
        return if !$_VALID_ALGORITHMS_LOOKUP{$algorithm};
    }
    else {
        $algorithm = $_DEFAULT_ALGORITHM;
    }
    if ( $algorithm eq 'rsa2' ) {
        $algorithm = 'rsa';
    }

    #validate name
    my $name = $OPTS{'name'};
    if ( length($name) ) {
        return if !_filename_is_valid($name);
        if ( $_RESERVED_KEY_NAMES_LOOKUP{$name} ) {
            $Cpanel::CPERROR{'ssh'} = "$name is a reserved key name. Please choose another name.";
            return;
        }
    }
    elsif ( $algorithm eq 'dsa' ) {
        $name = 'id_dsa';
    }
    else {
        $name = 'id_rsa';
    }

    #validate bits
    my $bits = $OPTS{'bits'};
    if ( defined $bits ) {
        return if $bits =~ m{\D} || $bits > 4096 || $bits < 768;
    }
    else {
        $bits = $algorithm eq 'dsa' ? 1024 : 4096;
    }

    #validate passphrase
    my @warnings;
    my $passphrase = $OPTS{'passphrase'};
    if ( defined $passphrase && length $passphrase ) {
        if ( length $passphrase >= 5 ) {
            my $passphrase_check = Cpanel::PasswdStrength::Check::check_password_strength(
                'pw'  => $passphrase,
                'app' => 'sshkey',
            );

            if ( !$passphrase_check ) {
                my $required_strength = Cpanel::PasswdStrength::Check::get_required_strength('sshkey');
                $Cpanel::CPERROR{'ssh'} = "The passphrase must have a strength rating of at least $required_strength.";
                return;
            }
        }
        else {
            $Cpanel::CPERROR{'ssh'} = "The passphrase must be at least 5 characters long.";
            return;
        }
    }
    else {
        push @warnings, 'SECURITY RISK: The passphrase is empty. This is allowed but STRONGLY discouraged. Please consider deleting the generated key pair and creating a new one with a strong passphrase.';
    }

    my $user = _get_user( $OPTS{'user'} );
    return if !$user;

    my $sshdir = _getsshdir($user);
    return if !$sshdir;

    my $key_path = $sshdir . '/' . $name;

    my $comment = length $OPTS{'comment'} ? Cpanel::StringFunc::Trim::ws_trim( $OPTS{'comment'} ) : q{};

    # Don't run ssh-keygen if the key already exists
    # It will just pause on "already exists, Overwrite (y/n)"
    # without actually doing anything.  We'll just end up
    # returning a false success status to the caller when no
    # key had actually been generated
    if ( $OPTS{'abort_on_existing_key'} ) {
        if ( -e $key_path ) {
            $Cpanel::CPERROR{'ssh'} = "$key_path already exists";
            return;
        }
    }

    my $output_hr = Cpanel::SafeRun::Full::run(
        'program' => '/usr/local/cpanel/bin/secure_ssh_keygen',
        'timeout' => $SSH_KEY_OPERATION_TIMEOUT,
        'args'    => ['--stdin'],
        'stdin'   => Cpanel::JSON::Dump(
            {
                command     => 'NEWKEY',
                password    => $passphrase,
                seckey_file => $key_path,
                type        => $algorithm,
                bits        => $bits,
                comment     => $comment,
            }
        )
    );
    my $result = 0;
    if ( $output_hr->{exit_value} == 0 && $output_hr->{'stdout'} ) {
        $result = 1;
    }
    else {
        my $key_error = $output_hr->{'stderr'} || $output_hr->{'stdout'};
        $Cpanel::CPERROR{'ssh'} = "SSH key generation failed: $key_error.";
    }

    return $result, \@warnings, [ split( /\n/, $output_hr->{'stdout'} ) ];    #\@output is for API2
}

sub api2_authkey {
    my %OPTS = @_;

    #legacy support
    #when Perl 5.10 is usable with perlcc, use the //= operator
    if ( !defined $OPTS{'name'} ) {
        my $name = $OPTS{'key'};
        $name =~ tr{/ \t\r\n\f}{}d;
        $name =~ s/\.\.//g;
        if ( $name !~ m{\.pub\z} ) {
            $name .= '.pub';
        }

        $OPTS{'file'} = $name;
    }
    if ( !defined $OPTS{'authorize'} ) {

        #mimic API2 behavior from before XML-API v1
        $OPTS{'authorize'} = !defined $OPTS{'action'} || $OPTS{'action'} !~ m{deauthorize}i ? 1 : 0;
    }

    my ( $filename, $authorized ) = _authkey(%OPTS);
    return { 'name' => $filename, 'status' => $authorized ? 'authorized' : 'deauthorized' };
}

# NB: This gets called from multiple external modules and is,
# practically speaking, a public interface, despite its name.
#
# Args:
#   user: optional (default: login)
#   file: this or text
#   authorize: required
#   text: this or file (text overrides)
#   options: text to prefix onto the authorized_keys line
#
sub _authkey {    ## no critic (ProhibitExcessComplexity) -- Not going to refactor this right now.
    my %OPTS = @_;

    return if !main::hasfeature('ssh');

    if ( $Cpanel::CPDATA{'DEMO'} ) {
        my $locale = Cpanel::Locale->get_handle();
        $Cpanel::CPERROR{'ssh'} = $locale->maketext('Sorry, this feature is disabled in demo mode.');
        return;
    }

    my $to_authorize = 0;
    my $auth_opt     = $OPTS{'authorize'} // q<>;

    if ( $auth_opt eq '1' ) {
        $to_authorize = 1;
    }
    elsif ( $auth_opt eq '0' ) {
        $to_authorize = 0;
    }
    else {
        $Cpanel::CPERROR{'ssh'} = locale()->maketext( 'The “[_1]” parameter’s value must be [list_or_quoted,_2].', 'authorize', [ 0, 1 ] );
        return;
    }

    my $user = _get_user( $OPTS{'user'} );
    return if !defined $user;

    my $sshdir = _getsshdir($user);
    return if !$sshdir;

    my $keydata = $OPTS{'text'};

    if ($keydata) {
        $keydata = Cpanel::StringFunc::Trim::ws_trim($keydata);
    }
    else {
        my $key_file = $OPTS{'file'};
        return if !_filename_is_valid($key_file);

        if ( open my $kf_fh, '<', "$sshdir/$key_file" ) {
            while ( defined( my $line = readline $kf_fh ) ) {
                $line = Cpanel::StringFunc::Trim::ws_trim($line);
                if ( $line ne q{} ) {
                    $keydata = $line;
                }
            }
            close $kf_fh;
        }
    }

    if ( !$keydata ) {
        $Cpanel::CPERROR{'ssh'} = 'The request key is empty';
        return;
    }

    my $authorized = 0;

    # used for fixing up ownership of authorized key file #
    my ( $login, undef, $uid, $gid ) = Cpanel::PwCache::getpwnam($user);

    foreach my $akey (@_AUTHORIZED_KEYS_FILES) {
        my @KD;
        my $akey_path = $sshdir . '/' . $akey;

        # Don't add keys to, or create, the deprecated authorized keys file
        next if ( $akey eq $_DEPRECATED_KEY_FILE && ( $to_authorize || !-e $akey_path ) );

        if ( !-e $akey_path ) {
            Cpanel::FileUtils::TouchFile::touchfile($akey_path);
            if ( !-e $akey_path ) {
                $logger->warn("Could not create $akey_path: $!");
                $Cpanel::CPERROR{'ssh'} = "Could not create $akey_path: $!";
                next;
            }
        }
        my $safelock = Cpanel::SafeFile::safeopen( \*AFFH, '+<', $akey_path );
        if ( !$safelock ) {
            $logger->warn("Could not edit $akey_path");
            $Cpanel::CPERROR{'ssh'} = "Could not edit $akey_path: $!";
            return;
        }
        if ( $ENV{'USER'} eq 'root' ) {

            # only set directory ownership when running as root user #
            my $chown_result = chown $uid, $gid, *AFFH;
            if ( !$chown_result ) {
                $logger->warn(qq{could not set ownership on '$akey_path": $!});
                $Cpanel::CPERROR{'ssh'} = "Could not properly create or modify $akey_path: $!";
                next;
            }
            my $chmod_result = chmod 0600, *AFFH;
            if ( !$chmod_result ) {
                $logger->warn(qq{could not set permissions to 0600 on '$akey_path": $!});
                $Cpanel::CPERROR{'ssh'} = "Could not properly create or modify $akey_path: $!";
                next;
            }
        }

        my $found_key;
      LINELOOP:
        while ( my $line = <AFFH> ) {
            $line = Cpanel::StringFunc::Trim::ws_trim($line);
            next LINELOOP if $line eq q{};
            if ( $line =~ m{\Q$keydata\E\z} ) {
                $found_key = 1;
                next LINELOOP;
            }
            push @KD, $line;
        }

        if ($to_authorize) {
            my $trimmed_options = length $OPTS{'options'} ? Cpanel::StringFunc::Trim::ws_trim( $OPTS{'options'} ) : q<>;

            if ( length $trimmed_options ) {
                push @KD, "$trimmed_options $keydata";
            }
            else {
                push @KD, $keydata;
            }
            $authorized = 1;
        }

        seek( AFFH, 0, 0 );
        print AFFH join( "\n", @KD ) . "\n";
        truncate( AFFH, tell(AFFH) );
        Cpanel::SafeFile::safeclose( \*AFFH, $safelock );
    }

    return wantarray ? ( $OPTS{'file'}, $authorized ) : $authorized;
}

sub api2_listkeys {
    my %OPTS = @_;

    $OPTS{'pub'} //= '';

    #API2 has "types" and "pub" parameters that give the same information.
    #The logic of the old function is duplicated here.
    my $pub  = $OPTS{'pub'} || ( $OPTS{'pub'} eq '' && $OPTS{'keys'} && $OPTS{'keys'} =~ m/\.pub$/ ) || $OPTS{'types'} eq 'pub';
    my $priv = !$pub;

    my %real_opts = (
        'public'          => 1,       #need this to determine "haspub"
        'private'         => $priv,
        'public_texts'    => 0,
        'private_texts'   => 0,
        'sync_authorized' => 1,
    );

    my ( $returned_keys_ar, $warnings_ar ) = _listkeys(%real_opts);
    return if !defined $returned_keys_ar || !@{$returned_keys_ar};

    my $key_to_list = $OPTS{'keys'};

    # Append .pub if requesting public key
    if ( $key_to_list && $pub && $key_to_list !~ /\.pub$/ ) {
        $key_to_list .= '.pub';
    }

    my $user    = _get_user();
    my $ssh_dir = _getsshdir($user);

    my @api2_keys;
    for my $key_data ( @{$returned_keys_ar} ) {
        next if defined $key_to_list && $key_data->{'file'} ne $key_to_list;

        next if !$priv && $key_data->{'private'};
        next if !$pub  && !$key_data->{'private'};

        #the old function ensured that every authorized key was written to disk
        #and replaced the "name" with the filename minus the .pub extension
        my $api2_name = $key_data->{'file'};
        next if !$api2_name;

        $api2_name =~ s{\.pub\z}{};

        my ( $haspub, $authaction, $authstatus );
        if ( $key_data->{'private'} ) {
            ( $authaction, $authstatus ) = ( 0, 0 );
            $haspub = grep { $_->{'file'} eq $key_data->{'file'} . '.pub' } @{$returned_keys_ar};
        }
        else {
            $haspub = 0;

            if ( $key_data->{'authorized'} ) {
                ( $authaction, $authstatus ) = ( 'Deauthorize', 'authorized' );
            }
            else {
                ( $authaction, $authstatus ) = ( 'Authorize', 'not authorized' );
            }
        }

        my %api2_specific_data = (
            'auth'       => $key_data->{'authorized'},
            'authaction' => $authaction,
            'authstatus' => $authstatus,
            'ctime'      => $key_data->{'ctime'},
            'file'       => $ssh_dir . '/' . $key_data->{'file'},
            'haspub'     => $haspub ? 1 : 0,
            'key'        => $key_data->{'file'},
            'mtime'      => $key_data->{'mtime'},
            'name'       => $api2_name,
        );

        push @api2_keys, \%api2_specific_data;
    }

    my $xform_cr = sub { my $n = shift()->{'name'}; defined $n ? $n : q{} };

    return Cpanel::Sort::list_sort( \@api2_keys, $xform_cr );
}

sub _listkeys {
    return if !main::hasfeature('ssh');

    my %args = @_;

    my $user = _get_user( $args{'user'} );
    return if !$user;

    my %files_to_list;
    if ( $args{'files'} ) {
        if ( ref $args{'files'} eq 'ARRAY' ) {
            @files_to_list{ @{ $args{'files'} } } = (1) x scalar @{ $args{'files'} };
        }
        else {
            $files_to_list{ $args{'files'} } = 1;
        }
    }

    #default to returning only public keys; private keys are by special request;
    #of course, if we were fed a list of files, then defer to that list
    my $list_private_keys;
    my $list_public_keys;
    if ( scalar %files_to_list ) {
        $list_private_keys = 1;
        $list_public_keys  = 1;
    }
    else {
        $list_private_keys = $args{'private'};
        $list_public_keys  = !defined( $args{'public'} ) || $args{'public'};
    }

    #do not do useless stuff
    return if !$list_private_keys && !$list_public_keys;

    my $ssh_dir = _getsshdir($user);
    return if !$ssh_dir;

    my $return_public_texts  = !defined( $args{'public_texts'} ) || $args{'public_texts'};
    my $return_private_texts = $args{'private_texts'};

    ## Handle all individual key files

    my %keys;
    my @warnings;

    if ( opendir my $ssh_dir_dh, $ssh_dir ) {
      FILELOOP:
        foreach my $file ( grep( !/^\./, readdir $ssh_dir_dh ) ) {
            next FILELOOP if $file =~ m{$INVALID_FILENAME_REGEX};
            next FILELOOP if $_RESERVED_KEY_NAMES_LOOKUP{$file};
            next FILELOOP if %files_to_list && !$files_to_list{$file};

            my $key_path = "$ssh_dir/$file";
            next FILELOOP if !-f $key_path;

            if ( $file =~ m/\.pub$/ && $list_public_keys ) {
                my $file_contents = Cpanel::StringFunc::Trim::ws_trim( Cpanel::LoadFile::loadfile($key_path) );
                if ( defined $file_contents ) {

                    #filter out private keys
                    next FILELOOP if $file_contents =~ m{\A[^\n]+PRIVATE\s+KEY\s*-+\s*\n}i;

                    my $key_line = $file_contents;
                    $key_line =~ tr{\n\r}{}d;    #make the key all one line

                    my ( $header, $b64, $comment ) = $key_line =~ m{\A$PUBLIC_SSH2_KEY_REGEX\z};

                    my $index;
                    if ( defined $b64 ) {
                        $index = $comment ? "$header $b64 $comment" : "$header $b64";
                    }
                    else {
                        my @match = $file_contents =~ m{\A$PUBLIC_RSA1_KEY_REGEX\z};
                        next FILELOOP if !@match;
                        $index   = join( q{ }, @match[ 0 .. 2 ] );
                        $comment = $match[-1];
                    }

                    if ( exists $keys{$index} ) {
                        push @warnings, "The file $file duplicates the key in $keys{$index}{'file'}";
                        next FILELOOP;
                    }

                    my %key_data = (
                        'file'       => $file,
                        'private'    => 0,
                        'authorized' => 0,
                        'comment'    => $comment,
                    );
                    @key_data{ 'mtime', 'ctime' } = ( stat(_) )[ 9, 10 ];
                    if ($return_public_texts) {
                        $key_data{'text'} = $file_contents;
                    }

                    $keys{$index} = \%key_data;
                }
            }
            elsif ($list_private_keys) {
                my $file_contents = Cpanel::StringFunc::Trim::ws_trim( Cpanel::LoadFile::loadfile($key_path) );
                if ( defined $file_contents ) {
                    next FILELOOP if $file_contents !~ m{\A[^\n]+PRIVATE\s+KEY}i;
                    my $encrypted = $file_contents =~ m{\n[ \t]*Proc-Type:.*ENCRYPTED}s;
                    my $header    = '-----BEGIN OPENSSH PRIVATE KEY-----';
                    if ( $file_contents =~ /^$header/ ) {

                        # OpenSSH private keys in this format contain the string
                        # "openssh-key-v1\0", a 4-byte big-endian length of the
                        # following field, the encryption algorithm (or "none",
                        # if unencrypted), a 4-byte big-endian length of the
                        # following field, and the key derivation function
                        # algorithm name (or "none"), followed by additional
                        # data.
                        #
                        # This base64-encoded data is the encoding of
                        # "openssh-key-v1\0\0\0\0\x04none\0", which is what all
                        # unencrypted keys start with.  If it doesn't match that
                        # pattern, it's either a newer format key we don't know
                        # about, or it's encrypted.
                        $encrypted = $file_contents !~ /^$header\s+b3BlbnNzaC1rZXktdjEAAAAABG5vbmUA/s;
                    }

                    my %key_data = (
                        'file'       => $file,
                        'private'    => 1,
                        'encrypted'  => $encrypted ? 1 : 0,
                        'authorized' => undef,
                        'comment'    => undef,
                    );
                    @key_data{ 'mtime', 'ctime' } = ( stat(_) )[ 9, 10 ];
                    if ($return_private_texts) {
                        $key_data{'text'} = $file_contents;
                    }

                    $keys{$file} = \%key_data;
                }
            }
        }
        closedir $ssh_dir_dh;
    }
    else {
        $Cpanel::CPERROR{'ssh'} = 'Unable to open SSH directory';
        return;
    }

    ## Handle authorized keys
    my %unnamed_authorized;
    @unnamed_authorized{@_AUTHORIZED_KEYS_FILES} = (0) x scalar @_AUTHORIZED_KEYS_FILES;
    if ($list_public_keys) {
        foreach my $ak_file (@_AUTHORIZED_KEYS_FILES) {
            next if !-e $ssh_dir . '/' . $ak_file;

            if ( open my $file_fh, '<', $ssh_dir . '/' . $ak_file ) {
              FILELOOP:
                while ( defined( my $line = readline $file_fh ) ) {
                    my $line = Cpanel::StringFunc::Trim::ws_trim($line);
                    next FILELOOP if $line eq q{} || $line =~ m{\A#};

                    my ( $options, $header, $b64, $comment ) = $line =~ m{\A$_AUTHORIZED_SSH2_KEY_REGEX\z};

                    my $index;
                    if ( defined $b64 ) {
                        $index = $comment ? "$header $b64 $comment" : "$header $b64";
                    }
                    else {
                        my @match = $line =~ m{\A$_AUTHORIZED_RSA1_KEY_REGEX\z};
                        next FILELOOP if !@match;
                        $index   = join( q{ }, @match[ 1 .. 3 ] );
                        $comment = $match[-1];
                    }

                    if ( exists $keys{$index} ) {
                        $keys{$index}{'authorized'} = $options || 1;
                    }
                    else {    #key only exists in authorized_keys/authorized_keys2
                        next FILELOOP if scalar %files_to_list;

                        my %key_data = (
                            'authorized' => $options || 1,
                            'file'       => undef,
                            'private'    => 0,
                            'mtime'      => undef,
                            'ctime'      => undef,
                            'comment'    => $comment,
                        );
                        if ($return_public_texts) {
                            $key_data{'text'} = $comment ? "$header $b64 $comment" : "$header $b64";
                        }

                        $unnamed_authorized{$ak_file}++;

                        $keys{$index} = \%key_data;
                    }
                }
                close $file_fh;
            }
        }
    }

    my $final_list_ar = [ sort { $a->{'file'} && $b->{'file'} ? $a->{'file'} cmp $b->{'file'} : ( $a->{'comment'} || '' ) cmp( $b->{'comment'} || '' ) } values %keys ];

    return $final_list_ar, \@warnings;
}

#not to be called directly, but also not a "utility" function per se
sub _importppk {
    my ( $sshdir, $name, $ppk_text, $opts ) = @_;

    return if !_filename_is_valid($name);

    my $pubkey_only = 0;

    if ( $name =~ m/^(.+)\.pub$/ ) {

        # case 103473
        #
        # ppk import works differently then import ssh key
        # when user enters the key in the public area, it appends a .pub
        # to the end of the name, we need to remove that for the remainder
        # of this routine, the remaining details are determined from the
        # key file provided

        $name        = $1;
        $pubkey_only = 1;
    }

    my $existing_name_keys_hr = _get_keys($sshdir);

    #store the extracted keys in temp files to ensure atomicity
    my $public_tmp;
    my $private_tmp;

    my $success = 1;

    #extract the public key manually
    if ( $opts->{'extract_public'} ) {
        my $public_key_filename = $name . '.pub';

        if ( $existing_name_keys_hr->{$public_key_filename} ) {
            $Cpanel::CPERROR{'ssh'} = "Import failed: public key $public_key_filename already exists.";
            return;
        }
        my $public_key = _extract_public_key_from_ppk( $ppk_text, $name );
        return if !$public_key;

        my $raw_key = _get_raw_key($public_key);

        my $existing_key_names_hr = { reverse %{$existing_name_keys_hr} };
        if ( my $existing = $existing_key_names_hr->{$raw_key} ) {
            $Cpanel::CPERROR{'ssh'} = "Import failed: extracted public key already exists in $existing.";
            return;
        }

        $public_tmp = Cpanel::Rand::gettmpfile();                                                                   # audit case 46806 ok
        $success    = Cpanel::FileUtils::Write::overwrite_no_exceptions( $public_tmp, $public_key . "\n", 0600 );
        if ( !$success ) {
            $Cpanel::CPERROR{'ssh'} = "Could not write temp file to disk: $!";
        }
    }

    # case 103473
    #
    # In the current implementation of the UI/api2, what gets passed in at the
    # top is just the key file and the key name, the rest is deduced.
    #
    # If keyname came in with a .pub, the key was entered in the public key
    # only box so ignore private key.
    #

    #getting the private key from a PuTTY file requires puttygen
    if ( $success && $opts->{'extract_private'} && $pubkey_only == 0 && $ppk_text =~ /Private-Lines: / ) {
        if ( $existing_name_keys_hr->{$name} ) {
            $Cpanel::CPERROR{'ssh'} = "Import failed: $sshdir/$name already exists";
            unlink $public_tmp;
            return;
        }

        my $pgen = Cpanel::Binaries::path('puttygen');
        if ( !-x $pgen ) {
            $Cpanel::CPERROR{'ssh'} = $pgen . ' is missing or not executable. To get the needed package, you should be able to run /usr/local/cpanel/scripts/check_cpanel_pkgs --targets=3rdparty --fix';
            unlink $public_tmp;
            return;
        }

        my $ppk_file = Cpanel::Rand::gettmpfile();    # audit case 46806 ok

        Cpanel::FileUtils::Write::overwrite_no_exceptions( $ppk_file, $ppk_text . "\n", 0600 );

        chmod( 0600, $ppk_file );

        my $existing_key_names_hr = { reverse %{$existing_name_keys_hr} };

        my $passphrase = defined $opts->{'passphrase'} ? $opts->{'passphrase'} : q{};

        #use a temp file to make sure we aren't bringing in a dupe key
        $private_tmp = Cpanel::Rand::gettmpfile();    # audit case 46806 ok

        my $output_hr = Cpanel::SafeRun::Full::run(
            'program' => $pgen,
            'args'    => [
                $ppk_file,
                '-O' => 'private-openssh',
                '-o' => $private_tmp,
                '-X',
            ],
            'stdin'   => $passphrase,
            'timeout' => $SSH_KEY_OPERATION_TIMEOUT,
        );

        if ( $output_hr->{'status'} ) {
            if ( $output_hr->{'stderr'} ) {
                $Cpanel::CPERROR{'ssh'} = $output_hr->{'stderr'};
                $success = 0;
            }
            elsif ( defined $output_hr->{'timeout'} ) {
                $Cpanel::CPERROR{'ssh'} = "Timeout while using puttygen to extract private key";
                $success = 0;
            }
            else {

                #check for a dupe key
                my $extracted_private = Cpanel::StringFunc::Trim::ws_trim( Cpanel::LoadFile::loadfile($private_tmp) );

                my $extracted_raw = _get_raw_key($extracted_private);

                #regex ensures no whitespace etc. messes things up
                my $existing = ( grep { m{\Q$extracted_raw\E} } keys %{$existing_key_names_hr} )[0];

                if ($existing) {
                    my $existing_file = $existing_key_names_hr->{$existing};
                    $Cpanel::CPERROR{'ssh'} = "Import failed: extracted private key already stored in $existing_file.";
                    $success = 0;
                }
            }
        }

        unlink $ppk_file;
    }

    if ($success) {
        my $new_private_file = "$sshdir/$name";
        my $new_public_file  = "$sshdir/$name.pub";

        if ( $success && $public_tmp ) {
            $success = Cpanel::FileUtils::Move::safemv( $public_tmp, $new_public_file );
            if ( !$success ) {
                $Cpanel::CPERROR{'ssh'} = "Error moving $public_tmp to $new_public_file: $!";
            }
        }

        if ( $success && $private_tmp ) {
            $success = Cpanel::FileUtils::Move::safemv( $private_tmp, $new_private_file );
            if ( !$success ) {
                $Cpanel::CPERROR{'ssh'} = "Error moving $private_tmp to $new_private_file: $!";
            }
        }
    }

    if ( !$success ) {
        unlink $private_tmp;
        unlink $public_tmp;
    }

    return $success ? $name : ();
}

sub _importkey {    ## no critic qw(RequireArgUnpacking Subroutines::ProhibitExcessComplexity) - its own project
    return if !main::hasfeature('ssh');

    if ( $Cpanel::CPDATA{'DEMO'} ) {
        my $locale = Cpanel::Locale->get_handle();
        $Cpanel::CPERROR{'ssh'} = $locale->maketext('Sorry, this feature is disabled in demo mode.');
        return;
    }

    my %OPTS = @_;

    my $key = $OPTS{'key'} && Cpanel::StringFunc::Trim::ws_trim( $OPTS{'key'} );
    return if !$key;    #duh, I need a key

    my $name = Cpanel::StringFunc::Trim::ws_trim( $OPTS{'name'} );
    $name =~ s/\.pub$//;
    return if !_filename_is_valid($name);

    my $user = _get_user( $OPTS{'user'} );
    return if !$user;

    my $sshdir = _getsshdir($user);
    return if !$sshdir;

    #go to the PuTTY key function, if that is what we are doing
    return _importppk( $sshdir, $name, $key, \%OPTS ) if $key =~ m{\APuTTY};

    my $existing_name_keys_hr = _get_keys($sshdir);

    #write the private key to a temp file if we only want the public key
    #this means that giving just "public" will not import the given key,
    #but giving neither "public" nor "private" will.

    #NOTE: This is where we EXTRACT public keys.
    #*Private* keys go here, not public.
    if ( $OPTS{'extract_public'} ) {
        if ( $existing_name_keys_hr->{"$name.pub"} ) {
            $Cpanel::CPERROR{'ssh'} = "Public key $name.pub already exists.";
            return;
        }
        else {

            my $submitted_key_path = Cpanel::Rand::gettmpfile();    # audit case 46806 ok
            Cpanel::FileUtils::Write::overwrite_no_exceptions( $submitted_key_path, $key . "\n", 0600 );

            my $output_hr = Cpanel::SafeRun::Full::run(
                'program' => '/usr/local/cpanel/bin/secure_ssh_keygen',
                'timeout' => $SSH_KEY_OPERATION_TIMEOUT,
                'args'    => ['--stdin'],
                'stdin'   => Cpanel::JSON::Dump(
                    {
                        command     => 'PUBKEY_FROM_SECKEY',
                        password    => $OPTS{'passphrase'},
                        seckey_file => $submitted_key_path
                    }
                )
            );

            if ( $output_hr->{'status'} ) {
                if ( $output_hr->{'exit_value'} != 0 ) {
                    $Cpanel::CPERROR{'ssh'} = "ssh-keygen command failed: $output_hr->{'stdout'}";
                }
                elsif ( $output_hr->{'timeout'} ) {
                    $Cpanel::CPERROR{'ssh'} = "Timeout while extracting public key.";
                }
                else {
                    my $extracted_public_key = $output_hr->{'stdout'};

                    if ($extracted_public_key) {
                        my $raw_public_key = _get_raw_key($extracted_public_key);

                        my @existing_names = grep { $existing_name_keys_hr->{$_} eq $raw_public_key } keys %{$existing_name_keys_hr};
                        if (@existing_names) {
                            my $display_existing = join( ', ', @existing_names );
                            $Cpanel::CPERROR{'ssh'} = "Public key extraction failed: extracted key already exists as $display_existing.";
                        }
                        else {
                            my $new_filename = "$sshdir/$name.pub";
                            if ( open my $key_fh, '>', $new_filename ) {
                                print {$key_fh} $extracted_public_key;
                                close $key_fh;
                                chmod 0644, $new_filename;

                                #the extraction went fine, so make the private key permanent
                                if ( $OPTS{'extract_private'} ) {
                                    my $permanent_private_key_path = "$sshdir/$name";
                                    my $moved                      = Cpanel::FileUtils::Move::safemv(
                                        $submitted_key_path,
                                        $permanent_private_key_path,
                                    );
                                    if ($moved) {
                                        return $name;
                                    }
                                    else {
                                        unlink $new_filename;
                                        $Cpanel::CPERROR{'ssh'} = "Moving private key failed: $!";
                                    }
                                }
                                else {
                                    unlink $submitted_key_path;
                                    return $name;
                                }
                            }
                            else {
                                $Cpanel::CPERROR{'ssh'} = "Could not open $new_filename for writing public key file.";
                            }
                        }
                    }
                    else {
                        $Cpanel::CPERROR{'ssh'} = "Could not extract public key.";
                    }
                }
            }
            else {
                $Cpanel::CPERROR{'ssh'} = $output_hr->{'message'} . $output_hr->{'stderr'};
            }

            unlink $submitted_key_path;
        }
    }
    else {    #import a key directly (public *or* private)
        my $valid = is_valid_public_key($key);

        if ($valid) {
            if ( $name !~ m{\.pub} ) {
                $name .= '.pub';
            }
        }
        else {
            $valid = is_valid_private_key($key);
        }

        if ($valid) {
            if ( $existing_name_keys_hr->{$name} ) {
                $Cpanel::CPERROR{'ssh'} = "Import failed: key file $name already exists.";
            }
            else {
                my $existing_key_names_hr = { reverse %{$existing_name_keys_hr} };
                my $raw_key               = _get_raw_key($key);

                if ( my $existing = $existing_key_names_hr->{$raw_key} ) {
                    $Cpanel::CPERROR{'ssh'} = "Import failed: submitted key already exists as $existing.";
                }
                else {
                    my $submitted_key_path = "$sshdir/$name";

                    if ( Cpanel::FileUtils::Write::overwrite_no_exceptions( $submitted_key_path, $key . "\n", 0600 ) ) {
                        chmod( 0600, $submitted_key_path );
                        if ( $ENV{'USER'} eq 'root' ) {

                            # only set directory ownership when running as root user #
                            my ( $login, undef, $uid, $gid ) = Cpanel::PwCache::getpwnam($user);
                            my $chown_result = chown $uid, $gid, $submitted_key_path;
                            if ( !$chown_result ) {
                                $Cpanel::CPERROR{'ssh'} = $!;
                                return;
                            }
                        }
                        return $name;
                    }
                    else {
                        $Cpanel::CPERROR{'ssh'} = "Could not write key to $submitted_key_path";
                    }
                }
            }
        }
        else {
            $Cpanel::CPERROR{'ssh'} = "Invalid key.";
        }

    }

    return;
}

sub api2_importkey {
    my %OPTS = @_;
    my $name = $OPTS{'name'} || 'id_dsa';
    $name =~ tr{/ \t\r\n\f}{}d;
    $name =~ s/\.\.//g;
    return if !$name;

    my $pass = $OPTS{'pass'};

    #not documented...?
    if ( $name =~ /^\./ ) { $name = 'id_dsa' . $name; }

    my @extra_opts;
    my $key = $OPTS{'key'};

    if ( $key =~ m{\A\s*PuTTY}m ) {
        push @extra_opts, ( 'extract_public' => 1, 'extract_private' => 1 );
    }

    my $realname = _importkey(
        'passphrase' => $pass,
        'user'       => $Cpanel::user,
        'name'       => $name,
        'key'        => $key,
        @extra_opts,
    );

    my @RSD;
    push @RSD, { 'name' => $realname };
    return @RSD;
}

sub api2_fetchkey {
    my %OPTS = @_;
    my $name = $OPTS{'name'};
    $name =~ tr{/ \t\r\n\f}{}d;
    $name =~ s/\.\.//g;
    if ( $OPTS{'pub'} && $name !~ m{\.pub\z} ) {
        $name .= q{.pub};
    }

    $OPTS{'file'} = $name;
    delete $OPTS{'name'};
    delete $OPTS{'pub'};

    my ( $keys_ar, $warnings_ar ) = _listkeys( 'files' => $name, 'public_texts' => 1, 'private_texts' => 1, );
    my $key_text = defined $keys_ar && defined $keys_ar->[0] && $keys_ar->[0]->{'text'};

    my @RSD;
    push @RSD,
      {
        'name' => $name,
        'key'  => $key_text || undef,
      };

    return @RSD;
}

sub _delkey {
    return if !main::hasfeature('ssh');

    if ( $Cpanel::CPDATA{'DEMO'} ) {
        my $locale = Cpanel::Locale->get_handle();
        $Cpanel::CPERROR{'ssh'} = $locale->maketext('Sorry, this feature is disabled in demo mode.');
        return;
    }

    my %OPTS = @_;

    my $user = _get_user( $OPTS{'user'} );
    return if !defined $user;

    my $sshdir = _getsshdir($user);
    return if !defined $sshdir;

    my $file = $OPTS{'file'};
    return if !_filename_is_valid($file);

    my $pub = $file =~ m{\.pub};

    my $success = 1;
    if ( $pub && !$OPTS{'leave_authorized'} ) {
        my $deauth = _authkey( 'user' => $user, 'file' => $file, 'authorize' => 0, );
        $success = defined $deauth;
    }

    my $keyfile = $sshdir . '/' . $file;
    if ($success) {
        $success = unlink $keyfile;
    }

    if ($success) {
        return wantarray ? ( $success, $keyfile ) : $success;
    }
    else {
        $Cpanel::CPERROR{'ssh'} = "Could not delete $keyfile.";
        return;
    }
}

sub api2_delkey {
    my %OPTS = @_;
    my $name = $OPTS{'name'};
    $name =~ tr{/ \t\r\n\f}{}d;
    $name =~ s/\.\.//g;
    if ( $OPTS{'pub'} && $name !~ m{\.pub\z} ) {
        $name .= '.pub';
    }

    $OPTS{'file'} = $name;
    delete $OPTS{'name'};
    delete $OPTS{'pub'};

    my @result = _delkey(%OPTS);
    return $result[0]
      ? { 'name' => $name, 'keyfile' => $result[1], 'leave_authorized' => $OPTS{'leave_authorized'}, }
      : ();
}

my $allow_demo             = { allow_demo    => 1 };
my $ssh_feature_deny_demo  = { needs_feature => "ssh" };
my $ssh_feature_allow_demo = { needs_feature => "ssh", allow_demo => 1 };

our %API = (
    authkey => {
        modify        => 'none',
        xss_checked   => 1,
        func          => 'api2_authkey',
        needs_feature => "ssh",
    },
    converttoppk  => $ssh_feature_deny_demo,
    delkey        => $ssh_feature_deny_demo,
    fetchkey      => $ssh_feature_allow_demo,
    genkey        => $ssh_feature_deny_demo,
    genkey_legacy => $ssh_feature_deny_demo,
    importkey     => {
        modify        => 'none',
        xss_checked   => 1,
        needs_feature => "ssh",
    },
    listkeys => $ssh_feature_allow_demo,
);

sub api2 {
    my ($func) = @_;
    return { %{ $API{$func} } } if $API{$func};
    return;
}

#----------------------------------------------------------------------
# Utility functions

sub _get_raw_key {
    my $full_key = shift || return;
    $full_key = Cpanel::StringFunc::Trim::ws_trim($full_key);
    my $raw_key;

    if ( $full_key =~ m{\A$PUBLIC_SSH2_KEY_REGEX\z} ) {
        $raw_key = $2;
    }
    elsif ( $full_key =~ m{\A$PRIVATE_SSH2_KEY_REGEX\z} ) {
        $raw_key = $3;
    }
    elsif ( $full_key =~ m{\A$PUBLIC_RSA1_KEY_REGEX\z} ) {
        $raw_key = $3;
    }
    elsif ( $full_key =~ m{\A$_PRIVATE_RSA1_KEY_REGEX\z} ) {
        $raw_key = $full_key;
    }
    else {
        return;
    }

    $raw_key =~ tr{ \t\n\r\f}{}d;    #remove whitespace

    return $raw_key;
}

#useful for preventing imports of duplicate keys
my %_Cached_Keys;

sub _get_keys {
    my $sshdir = shift() || return;

    if ( my $cached = $_Cached_Keys{$sshdir} ) {
        return $cached;
    }

    my %keys;

    if ( opendir my $dh, $sshdir ) {
        my @all_files = readdir $dh;
        close $dh;

        local $/;
        foreach my $cur_file (@all_files) {
            next if $cur_file =~ m{$INVALID_FILENAME_REGEX};
            next if $_RESERVED_KEY_NAMES_LOOKUP{$cur_file};
            my $full_path = "$sshdir/$cur_file";
            if ( -f $full_path && open my $fh, '<', $full_path ) {
                my $raw_key = _get_raw_key( readline $fh );

                if ($raw_key) {
                    $keys{$cur_file} = $raw_key;
                }

                close $fh;
            }
        }

        $_Cached_Keys{$sshdir} = \%keys;

        return wantarray ? %keys : \%keys;
    }
    else {
        $Cpanel::CPERROR{'ssh'} = "Could not open $sshdir.";
    }

    return;
}

sub _get_user {
    my $requested_user = shift();
    my $user;

    if ( defined $requested_user ) {
        if ( Whostmgr::ACLS::hasroot() ) {
            $user = $requested_user;
        }
        else {
            my $detected_user = $Cpanel::user || $ENV{'REMOTE_USER'} || ( Cpanel::PwCache::getpwuid($>) )[0];

            if ( $requested_user eq $detected_user ) {
                $user = $detected_user;
            }
            else {
                $Cpanel::CPERROR{'ssh'} = "Invalid access";
                return;
            }
        }
    }
    else {
        $user = $Cpanel::user || ( Cpanel::PwCache::getpwuid($>) )[0];
    }

    if ( !$user ) {
        $Cpanel::CPERROR{'ssh'} = "User error";
        return;
    }

    return $user || ();
}

my %_Cached_puttysshdir;

sub _getputtysshdir {
    my $user = shift;

    return $_Cached_puttysshdir{$user} if exists $_Cached_puttysshdir{$user};

    my $sshdir = _getsshdir($user);
    return if !$sshdir;

    my $puttysshdir = $sshdir . '/putty';

    if ( !-e $puttysshdir ) {
        my $mk_result = mkdir( $puttysshdir, 0700 );
        if ( !$mk_result ) {
            $Cpanel::CPERROR{'ssh'} = "Could not create $puttysshdir: $!";
            return;
        }
    }
    elsif ( !-d $puttysshdir ) {
        $Cpanel::CPERROR{'ssh'} = "$puttysshdir exists as a non-directory.";
        return;
    }

    $_Cached_puttysshdir{$user} = $puttysshdir;
    return $puttysshdir;
}

my %_Cached_sshdir;

sub _getsshdir {
    my ( $user, $opts ) = @_;
    $opts //= {};

    my $cached = $_Cached_sshdir{$user};
    return $cached if $cached;

    my $homedir = Cpanel::PwCache::gethomedir($user);
    if ( !$homedir ) {
        $Cpanel::CPERROR{'ssh'} = "Could not find home directory for $user.";
        return;
    }

    my $sshdir = $homedir . '/.ssh';

    if ( !-e $sshdir && !$opts->{'skip_create'} ) {
        my $mk_result = mkdir( $sshdir, 0700 );
        if ( !$mk_result ) {
            $Cpanel::CPERROR{'ssh'} = $!;
            return;
        }
        if ( $ENV{'USER'} eq 'root' ) {

            # only set directory ownership when running as root user #
            my ( $login, undef, $uid, $gid ) = Cpanel::PwCache::getpwnam($user);
            my $chown_result = chown $uid, $gid, $sshdir;
            if ( !$chown_result ) {
                $Cpanel::CPERROR{'ssh'} = $!;
                return;
            }
        }
    }

    $_Cached_sshdir{$user} = $sshdir;
    return $sshdir;
}

#this can be done manually without the passphrase
sub _extract_public_key_from_ppk {
    my $ppk_text = shift();
    my $name     = shift();

    $ppk_text =~ m{\APuTTY[^:]+:\s+(\S+)}m;
    my $algorithm = $1;
    if ( !$algorithm ) {
        $Cpanel::CPERROR{'ssh'} = "Could not identify algorithm.";
        return;
    }

    if ( $ppk_text !~ m{^Public-Lines}ms ) {
        $Cpanel::CPERROR{'ssh'} = "Could not extract public key.";
        return;
    }

    # I need precise control of the lines so throw me out of the perl
    # programming guild for using c style for loops

    my $i;
    my $len;
    my $num_public_lines = 0;

    $ppk_text =~ s/\r//g;    # this comes from Windoze, will have cr's
    my @lines = split( /\n/, $ppk_text );
    $len = @lines;

    # The ppk file tells us how many lines of public key there is
    for ( $i = 0; $i < $len; ++$i ) {
        my $line = $lines[$i];
        if ( $line =~ m/^Public-Lines: (\d+)$/ ) {
            $num_public_lines = $1;
            last;
        }
    }

    my $public_key_text = "";
    $i++;
    for ( my $j = 0; $j < $num_public_lines; ++$j ) {
        my $line = $lines[ $i + $j ];
        $public_key_text .= $line . "\n";
    }

    $public_key_text =~ s{\s+}{}g;
    return if !$public_key_text;
    if ( !$public_key_text ) {
        $Cpanel::CPERROR{'ssh'} = "Could not extract public key.";
        return;
    }

    my $time_comment = localtime();
    $time_comment =~ s{\s}{_}g;
    my @key = ( $algorithm, $public_key_text, $time_comment, $name );

    return wantarray ? @key : join( q{ }, @key );
}

sub _filename_is_valid {
    my $filename = $_[0];
    my $valid    = defined $filename && $filename !~ m{$INVALID_FILENAME_REGEX};

    if ($valid) {
        return $valid;
    }
    else {
        $Cpanel::CPERROR{'ssh'} = 'Invalid filename';
    }

    return;
}

#----------------------------------------------------------------------

sub is_valid_public_key {
    my $key_in = shift();
    return $key_in =~ m{\A$PUBLIC_SSH2_KEY_REGEX\z} || $key_in =~ m{\A$PUBLIC_RSA1_KEY_REGEX\z}
      ? $key_in
      : ();
}

sub is_valid_private_key {
    my $key_in = shift();
    return $key_in =~ m{\A$PRIVATE_SSH2_KEY_REGEX\z} || $key_in =~ m{\A$_PRIVATE_RSA1_KEY_REGEX\z}
      ? $key_in
      : ();
}

sub split_ssh2_private_key {
    my $key_in = shift();
    my @split  = ( $key_in =~ m{\A$PRIVATE_SSH2_KEY_REGEX\z} );
    return @split;
}

sub split_rsa1_public_key {
    my $key   = shift();
    my @split = $key =~ m{\A$PUBLIC_RSA1_KEY_REGEX\z};
    return @split;
}

#from Crypt::RSA::Key::Private::SSH...
#This returns:
#   0) The text "SSH PRIVATE KEY FILE FORMAT 1.1\n" (32 bytes)
#   1) cipher type (single byte, 0x00 if unencrypted)
#   2) modulus as binary
#   3) exponent as binary
#   4) comment
#   ...and nothing more, since stuff after this can be encrypted
sub split_rsa1_private_key {
    my $key = shift;
    my @split;

    push @split, substr( $key, 0,  32 );    #text
    push @split, substr( $key, 33, 1 );     #cipher type

    my $modulus_bits = unpack( 'N', substr( $key, 38, 4 ) );
    push @split, $modulus_bits;

    #byte 42 (0x2a) is the 2-byte bit length of the modulus;
    #byte 44 (0x2c) is the modulus itself
    my $modulus_bytes = int( ( $modulus_bits + 7 ) ) / 8;    #round up
    push @split, substr( $key, 44, $modulus_bytes );

    my $exponent_bits  = unpack( 'n', substr( $key, 44 + $modulus_bytes, 2 ) );
    my $exponent_bytes = int( ( $exponent_bits + 7 ) / 8 );
    push @split, substr( $key, 44 + $modulus_bytes + 2, $exponent_bytes );

    my $comment_bits  = unpack( 'n', substr( $key, 46 + $modulus_bytes + $exponent_bytes, 4 ) );
    my $comment_bytes = int( ( $comment_bits + 7 ) / 8 );
    push @split, substr( $key, 46 + $modulus_bytes + $exponent_bytes + 4, $comment_bytes );

    return wantarray ? @split : \@split;
}

#ASN.1 format, though this does not work if the key has a passphrase
#NB: RSA2 private keys are organized thus:
#    something ("noise"), modulus, public exponent, private exponent,
#    prime 1, prime 2, exponent 1, exponent 2, coefficient
#DSA keys are also ASN.1
sub split_base64_private_key {
    my $b64_key    = shift();
    my $binary_key = MIME::Base64::decode_base64($b64_key);

    #DSA/RSA2 private keys begin with an ASN.1 sequence, indicated by 0x30
    #return if it doesn't look right (i.e. there is probably a passphrase)
    return if ord( substr( $binary_key, 0, 1 ) ) != 0x30;

    Cpanel::LoadModule::load_perl_module('Cpanel::SSH::ASN');
    my $enc = Cpanel::SSH::ASN->new();
    $enc->decode($binary_key);
    my @body_items = $enc->get_sequence();

    return wantarray ? @body_items : \@body_items;
}

#DSA and RSA2 public keys have a format that sort of resembles ASN.1:
#repeated pairs of length-value; "length" is always 4 bytes
#NB: For RSA2, these are descriptor, exponent, modulus (with an initial zero)
#    For DSA, they are descriptor and several numbers (all with initial zeros)
sub split_base64_public_key {
    my $b64_key = shift();

    my $binary_key = MIME::Base64::decode_base64($b64_key);
    my $key_length = length $binary_key;

    my @split = ();

    my $item_length = unpack( 'N*', substr( $binary_key, 0, 4 ) );
    my $offset      = 4;
    while ( $item_length && $item_length + $offset <= $key_length ) {
        push @split, substr( $binary_key, $offset, $item_length );
        $offset += $item_length;
        $item_length = unpack( 'N', substr( $binary_key, $offset, 4 ) );
        $offset += 4;
    }

    return wantarray ? @split : \@split;
}

#works for RSA2 and DSA keys; DSA should always be 1024, but just in case
sub get_ssh2_private_bits {
    my $base64 = shift();

    my $bits;

    #will be undef if the key has a passphrase
    my @split = Cpanel::SSH::split_base64_private_key($base64);

    if (@split) {
        $bits = ( length( $split[1]->{'value'} ) - 1 ) * 8;

        #find how many initial bits are being used
        my $initial          = substr( $split[1]->{'value'}, 0, 1 );
        my $first_char_value = ord $initial;
        if ($first_char_value) {
            my $initial_bits = int( log($first_char_value) / log 2 ) + 1;
            $bits += $initial_bits;
        }
    }

    return $bits || ();
}

# Legacy code removed, so this now points to the SSH::genkey API
sub api2_genkey_legacy {
    goto &api2_genkey;
}

1;
