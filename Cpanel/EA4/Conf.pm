package Cpanel::EA4::Conf;

# cpanel - Cpanel/EA4/Conf.pm                      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::EA4::Conf::Tiny ();
our $CONFPATH = $Cpanel::EA4::Conf::Tiny::CONFPATH;
use Cpanel::Transaction::File::JSON       ();
use Cpanel::Transaction::File::JSONReader ();
use Cpanel::Debug                         ();
use Cpanel::OS                            ();

use Moo;
with 'Role::Multiton';

sub DEMOLISH {
    my ( $self, $in_global_destruction ) = @_;

    # quiet by default, but in case we want to know about not saving changes
    warn "Discarding unsaved EA4 Conf changes!\n" if $self->warn_unsaved && $self->is_dirty;

    return;
}

sub BUILD {
    my ( $self, $args ) = @_;

    my $trx = Cpanel::Transaction::File::JSONReader->new( path => $CONFPATH );

    my $data = $trx->get_data;
    my $hr   = {
        %{ ref($data) eq "SCALAR" ? {} : $data },
        %{$args},
    };

    $self->_set_hr( $hr, $args );

    return;
}

has is_dirty => (
    is      => "rwp",
    default => 0,
);

has warn_unsaved => (
    is      => "rw",
    default => 0,
    coerce  => sub { $_[0] ? 1 : 0 }
);

has conf_attrs => (
    is      => "ro",
    default => sub {

        # sort so that the order is predictable and so that sslprotocol comes before sslciphersuite
        return [ sort { $b cmp $a } grep { $_ ne "local_attrs" } keys %{ {Cpanel::EA4::Conf::Tiny::DEFAULTS} } ];
    },
);

has local_attrs => (    # special config attr for arbitrary local customization
    is      => "rwp",
    default => sub { _get_default('local_attrs') },
);

####################
#### config attrs ##
####################

has directoryindex => (
    is      => "rw",
    default => sub { _get_default('directoryindex') },
    trigger => sub { $_[0]->_set_is_dirty(1) },
    isa     => sub {
        my ($value) = @_;
        _valid_string($value);

        die "Index names cannot contain null bytes\n" if $value =~ m/\0/;
        die "Index names cannot be all whitespace\n"  if $value =~ m/^\s+$/;

        for my $filename ( split /\s+/, $value ) {
            die "Index names cannot be “.”\n"  if $filename eq ".";
            die "Index names cannot be “..”\n" if $filename eq "..";
        }

        return 1;
    },
);

# NOTE: normally there is nothing in the main file as there are no limits
# But if I selected the memory limits to be 372mb, this is the structure
# that is written out to the main file.
#
#  "rlimitcpu":
#    "directive": 'rlimitcpu'
#    "item":
#      "maxrlimitcpu": ''
#      "softrlimitcpu": 240
#  "rlimitmem":
#    "directive": 'rlimitmem'
#    "item":
#      "maxrlimitmem": ''
#      "softrlimitmem": 390070272

has rlimit_cpu_hard => (
    is      => "rw",
    default => sub { _get_default('rlimit_cpu_hard') },
    trigger => sub { $_[0]->_set_is_dirty(1) },
    isa     => \&_valid_empty_string_or_nonnegative_int,
);

has rlimit_cpu_soft => (
    is      => "rw",
    default => sub { _get_default('rlimit_cpu_soft') },
    trigger => sub { $_[0]->_set_is_dirty(1) },
    isa     => \&_valid_nonnegative_int,
);

has rlimit_mem_hard => (
    is      => "rw",
    default => sub { _get_default('rlimit_mem_hard') },,
    trigger => sub { $_[0]->_set_is_dirty(1) },
    isa     => \&_valid_empty_string_or_nonnegative_int,
);

has rlimit_mem_soft => (
    is      => "rw",
    default => sub { _get_default('rlimit_mem_soft') },,
    trigger => sub { $_[0]->_set_is_dirty(1) },
    isa     => \&_valid_empty_string_or_nonnegative_int,
);

my %ciphersuite = (
    ALL => "A pseudo alias for everything",

    # Key Exchange Algorithm:
    kRSA => "RSA key exchange",
    kDHr => "Diffie-Hellman key exchange with RSA key",
    kDHd => "Diffie-Hellman key exchange with DSA key",
    kEDH => "Ephemeral (temp.key) Diffie-Hellman key exchange (no cert)",
    kSRP => "Secure Remote Password (SRP) key exchange",

    # Authentication Algorithm:
    aNULL => "No authentication",
    aRSA  => "RSA authentication",
    aDSS  => "DSS authentication",
    aDH   => "Diffie-Hellman authentication",

    # Cipher Encoding Algorithm:
    eNULL  => "No encryption",
    NULL   => "alias for eNULL",
    AES    => "AES encryption",
    DES    => "DES encryption",
    "3DES" => "Triple-DES encryption",
    RC4    => "RC4 encryption",
    RC2    => "RC2 encryption",
    IDEA   => "IDEA encryption",

    # MAC Digest Algorithm:
    MD5    => "MD5 hash function",
    SHA1   => "SHA1 hash function",
    SHA    => "alias for SHA1",
    SHA256 => "SHA256 hash function",
    SHA384 => "SHA384 hash function",

    # Aliases:
    SSLv3    => "all SSL version 3.0 ciphers",
    TLSv1    => "all TLS version 1.0 ciphers",
    EXP      => "all export ciphers",
    EXPORT40 => "all 40-bit export ciphers only",
    EXPORT56 => "all 56-bit export ciphers only",
    LOW      => "all low strength ciphers (no export, single DES)",
    MEDIUM   => "all ciphers with 128 bit encryption",
    HIGH     => "all ciphers using Triple-DES",
    RSA      => "all ciphers using RSA key exchange",
    DH       => "all ciphers using Diffie-Hellman key exchange",
    EDH      => "all ciphers using Ephemeral Diffie-Hellman key exchange",
    ECDH     => "Elliptic Curve Diffie-Hellman key exchange",
    ADH      => "all ciphers using Anonymous Diffie-Hellman key exchange",
    AECDH    => "all ciphers using Anonymous Elliptic Curve Diffie-Hellman key exchange",
    SRP      => "all ciphers using Secure Remote Password (SRP) key exchange",
    DSS      => "all ciphers using DSS authentication",
    ECDSA    => "all ciphers using ECDSA authentication",
    aNULL    => "all ciphers using no authentication",
);

my %disallowed_ciphersuite = (
    aNULL => 1,
    eNULL => 1,
    NULL  => 1,
    EXP   => 1,
);

has sslciphersuite => (
    is      => "rw",
    default => sub { _get_default('sslciphersuite') },
    trigger => sub {
        my ( $self, $new_value ) = @_;

        $self->_set_is_dirty(1);

        my @final_list;
        my %seen_ciphers;
        my @given_ciphers = split /:/, $new_value;

        # we’re really coercing $new_value but we cannot use coerce because
        #    coerce only gets the value and we need the object’s sslprotocol
        for my $sslprotocol ( split /\s+/, $self->sslprotocol_list_str ) {
            my $flag = "";                        # TLSv1
            if ( $sslprotocol !~ m/^TLSv/i ) {    # SSLv…
                $flag = "_2";
            }
            elsif ( $sslprotocol =~ m/^TLSv1\.(\d)/i ) {    # TLSv1.…
                $flag = "_$1";
            }

            my $openssl     = Cpanel::OS::ea4_modern_openssl();
            my $single_line = "-s ";
            {
                local $!;
                if ( !-x $openssl ) {
                    $openssl     = '/opt/cpanel/ea-openssl/bin/openssl';
                    $flag        = "";
                    $single_line = "";
                }
            }

            local $?;
            local $!;
            my $valid_cyphers = `$openssl ciphers $single_line-tls1$flag`;    # qx() is simple and all we really need here, no real gain from bringing in other modules to do this for us
            Cpanel::Debug::log_debug("`$openssl ciphers $single_line-tls1$flag` failed (\$!: '$!')\n") if $? || $!;

            chomp $valid_cyphers;
            my @valid_ciphers = split /:/, $valid_cyphers;

            if ( $flag eq "_3" ) {
                require Cpanel::SSL::Defaults;
                my $default_cipher_list = Cpanel::SSL::Defaults::default_cipher_list();

                # if we are working off the defaults …
                if ( $new_value eq $default_cipher_list ) {
                    unshift @given_ciphers, @valid_ciphers;    # … ensure the TLSv1.3 ciphers are in play since TLSv1.3 is
                }

                push @valid_ciphers, split /:/, $default_cipher_list;
            }

            my %valid_cipher_lu;
            @valid_cipher_lu{@valid_ciphers} = ();
            for my $valid_cipher (@valid_ciphers) {
                my @parts = split( /[-+!]/, $valid_cipher );
                next if @parts == 1;
                for my $part (@parts) {
                    if ( !exists $ciphersuite{$part} ) {
                        $ciphersuite{$part} = "Added from “$valid_cipher”";
                    }
                }
            }

            my @new_list;
            my $already_have_ciphers = 0;
            for my $gc (@given_ciphers) {
                my $given_cypher = $gc;    # operate on a copy
                my $sign         = "";
                if ( rindex( $given_cypher, "+", 0 ) == 0 ) {
                    $sign = substr( $given_cypher, 0, 1, "" );
                }
                elsif ( rindex( $given_cypher, "-", 0 ) == 0 ) {
                    $sign = substr( $given_cypher, 0, 1, "" );
                }
                elsif ( rindex( $given_cypher, "!", 0 ) == 0 ) {
                    $sign = substr( $given_cypher, 0, 1, "" );
                }

                if ( exists $valid_cipher_lu{$given_cypher} || exists $ciphersuite{$given_cypher} ) {
                    $already_have_ciphers++ if exists $seen_ciphers{$given_cypher} && $seen_ciphers{$given_cypher} > 0;
                    next                    if exists $disallowed_ciphersuite{$given_cypher} && ( $sign eq "" || $sign eq "+" );
                    next                    if grep { $given_cypher =~ m/^\Q$_\E-/i || $given_cypher =~ m/\S-\Q$_\E(?:-|$)/i } keys %disallowed_ciphersuite;
                    $seen_ciphers{$given_cypher}++;
                    push @new_list, "$sign$given_cypher" if $seen_ciphers{$given_cypher} == 1;
                }
                else {
                    my @parts = split( /[-+!]/, $gc );
                    shift @parts if $parts[0] eq "";
                    my $invalid_count = @parts;

                    for my $part (@parts) {

                        # There is no good way to tell if $part is valid for at least one of the SSL protocols.
                        # That is probably ok though because, for it to be a problem, they’d have
                        #  to have a ciphersuite string entirely made up of arbitrary combinations
                        #  with none of $part’s being supported by any of the SSL protocols
                        $invalid_count-- if exists $ciphersuite{$part};
                    }

                    push @new_list, $gc if $invalid_count == 0;
                }
            }

            my %s;
            push @final_list,
                @new_list             ? @new_list
              : $already_have_ciphers ? ()
              :                         grep { $s{$_}++ == 0 } @valid_ciphers;
        }

        my %f;
        if ( !@final_list ) {
            require Cpanel::SSL::Defaults;
            @final_list = split /:/, Cpanel::SSL::Defaults::default_cipher_list();
        }

        return $self->{sslciphersuite} = join ":", grep { $f{$_}++ == 0 } @final_list;
    },
    isa => sub { _valid_tweaksetting( sslciphersuite => $_[0] ) },
);

has sslprotocol => (
    is      => "rw",
    default => sub { _get_default('sslprotocol') },
    trigger => sub {
        my ( $self, $new_value ) = @_;
        $self->_set_is_dirty(1);
        $self->sslciphersuite( $self->sslciphersuite ) if $new_value;
    },
    coerce => sub {
        local $@;
        eval { _valid_tweaksetting( sslprotocol => $_[0] ) };
        return $_[0] if !$@;

        return _get_default('sslprotocol');
    },
    isa => sub { _valid_tweaksetting( sslprotocol => $_[0] ) },
);

sub sslprotocol_list_str {
    my ($self) = @_;
    die "sslprotocol_list_str is a read-only accessor" if @_ > 1;    # as if it where a `ro` has()

    my @actual_protocols;

    my $sslprotocol_exp = $self->sslprotocol;
    my @sslprotocols    = map { lc($_) } split /\s+/, $sslprotocol_exp;

    require Cpanel::SSL::Defaults;
    my %norm_proto = map { lc($_) => $_ } keys %{ Cpanel::SSL::Defaults::ea4_all_protos() };
    if ( grep { $_ eq "all" } @sslprotocols ) {
        push @actual_protocols, keys %norm_proto;
    }

    for my $prot (@sslprotocols) {
        next if $prot eq "all";

        if ( $prot =~ m/^-(.*)$/ ) {
            my $remove = $1;
            @actual_protocols = grep { $_ ne $remove } @actual_protocols;
        }
        else {
            $prot =~ s/^\+//;
            push @actual_protocols, $prot;
        }
    }

    return join " ", sort map { $norm_proto{$_} } @actual_protocols;
}

has sslusestapling => (
    is      => "rw",
    default => sub { _get_default('sslusestapling') },
    trigger => sub { $_[0]->_set_is_dirty(1) },
    coerce  => \&_coerce_to_on_or_off,
    isa     => \&_valid_on_or_off,
);

has extendedstatus => (
    is      => "rw",
    default => sub { _get_default('extendedstatus') },
    trigger => sub { $_[0]->_set_is_dirty(1) },
    coerce  => \&_coerce_to_on_or_off,
    isa     => \&_valid_on_or_off,
);

has loglevel => (
    is      => "rw",
    default => sub { _get_default('loglevel') },
    trigger => sub { $_[0]->_set_is_dirty(1) },
    isa     => sub { _valid_tweaksetting( loglevel => $_[0] ) },
);

has root_options => (
    is      => "rw",
    default => sub { _get_default('root_options') },
    trigger => sub { $_[0]->_set_is_dirty(1) },
    isa     => sub {
        my @array = split / /, ( $_[0] // "" );
        return _valid_tweaksetting( root_options => \@array );    # 'None'?
    },
);

#    "logformat":
#      "directive": 'logformat'
#      "items":
#        -
#          "logformat": '"%v:%p %h %l %u %t \"%r\" %>s %b \"%{Referer}i\" \"%{User-Agent}i\"" combinedvhost'
#        -
#          "logformat": '"%v:%p %h %l %u %t \"%r\" %>s %b \"%{Referer}i\" \"%{User-Agent}i\"" combined'
#        -
#          "logformat": '"%v:%p %h %l %u %t \"%r\" %>s %b" common'
#        -
#          "logformat": '"%{Referer}i -> %U" referer'
#        -
#          "logformat": '"%{User-agent}i" agent'

has logformat_combined => (
    is      => "rw",
    default => sub { _get_default('logformat_combined') },
    trigger => sub { $_[0]->_set_is_dirty(1) },
    isa     => sub { _valid_tweaksetting( logformat_combined => $_[0] ) },
);

has logformat_common => (
    is      => "rw",
    default => sub { _get_default('logformat_common') },
    trigger => sub { $_[0]->_set_is_dirty(1) },
    isa     => sub { _valid_tweaksetting( logformat_common => $_[0] ) },
);

has traceenable => (
    is      => "rw",
    default => sub { _get_default('traceenable') },
    trigger => sub { $_[0]->_set_is_dirty(1) },
    isa     => sub { _valid_tweaksetting( traceenable => $_[0] ) },
);

has serversignature => (
    is      => "rw",
    default => sub { _get_default('serversignature') },
    trigger => sub { $_[0]->_set_is_dirty(1) },
    isa     => sub { _valid_tweaksetting( serversignature => $_[0] ) },
);

has servertokens => (
    is      => "rw",
    default => sub { _get_default('servertokens') },
    trigger => sub { $_[0]->_set_is_dirty(1) },
    isa     => sub { _valid_tweaksetting( servertokens => $_[0] ) },
);

has fileetag => (
    is      => "rw",
    default => sub { _get_default('fileetag') },
    trigger => sub { $_[0]->_set_is_dirty(1) },
    isa     => sub { _valid_tweaksetting( fileetag => $_[0] ) },
);

has startservers => (
    is      => "rw",
    default => sub { _get_default('startservers') },
    trigger => sub { $_[0]->_set_is_dirty(1) },
    isa     => sub { _valid_tweaksetting( startservers => $_[0] ) },
);

has minspareservers => (
    is      => "rw",
    default => sub { _get_default('minspareservers') },
    trigger => sub { $_[0]->_set_is_dirty(1) },
    isa     => sub { _valid_tweaksetting( minspareservers => $_[0] ) },
);

has maxspareservers => (
    is      => "rw",
    default => sub { _get_default('maxspareservers') },
    trigger => sub { $_[0]->_set_is_dirty(1) },
    isa     => sub { _valid_tweaksetting( maxspareservers => $_[0] ) },
);

has serverlimit => (
    is      => "rw",
    default => sub { _get_default('serverlimit') },
    trigger => sub {
        my ($self) = @_;
        $self->_set_is_dirty(1);
        require Cpanel::ConfigFiles::Apache::modules;
        if ( Cpanel::ConfigFiles::Apache::modules::apache_mpm_threaded() ) {

            if ( $self->maxclients > $self->serverlimit * $self->threadsperchild ) {
                $self->maxclients( $self->serverlimit * $self->threadsperchild );
            }
        }
        else {
            if ( $self->maxclients > $self->serverlimit ) {
                $self->maxclients( $self->serverlimit );
            }
        }
    },
    isa => sub { _valid_tweaksetting( serverlimit => $_[0] ) },
);

has threadsperchild => (
    is      => "rw",
    lazy    => 1,
    default => sub { _get_default('threadsperchild') },
    trigger => sub { $_[0]->_set_is_dirty(1) },
    isa     => \&_valid_nonnegative_int,
);

has servername => (
    is      => "ro",
    lazy    => 1,
    default => sub { _get_default('servername') },
);

has serveradmin => (
    is      => "ro",
    lazy    => 1,
    default => sub { _get_default('serveradmin') },
);

has maxclients => (
    is      => "rw",
    default => sub { _get_default('maxclients') },
    trigger => sub {
        my ($self) = @_;
        $self->_set_is_dirty(1);

        if ( !defined $self->serverlimit ) {
            $self->serverlimit( $self->maxclients );
            return;
        }

        require Cpanel::ConfigFiles::Apache::modules;
        if ( Cpanel::ConfigFiles::Apache::modules::apache_mpm_threaded() ) {

            if ( $self->maxclients > $self->serverlimit * $self->threadsperchild ) {
                if ( $self->threadsperchild ) {
                    $self->serverlimit( int( $self->maxclients / $self->threadsperchild + 0.5 ) );
                }
            }
        }
        else {
            if ( $self->maxclients > $self->serverlimit ) {
                $self->serverlimit( $self->maxclients );
            }
        }
    },
    isa => sub { _valid_tweaksetting( maxclients => $_[0] ) },
);

has maxrequestsperchild => (
    is      => "rw",
    default => sub { _get_default('maxrequestsperchild') },
    trigger => sub { $_[0]->_set_is_dirty(1) },
    isa     => sub { _valid_tweaksetting( maxrequestsperchild => $_[0] ) },
);

has keepalive => (
    is      => "rw",
    default => sub { _get_default('keepalive') },
    trigger => sub { $_[0]->_set_is_dirty(1) },
    coerce  => \&_coerce_to_on_or_off,
    isa     => \&_valid_on_or_off,
);

has keepalivetimeout => (
    is      => "rw",
    default => sub { _get_default('keepalivetimeout') },
    trigger => sub { $_[0]->_set_is_dirty(1) },
    isa     => sub { _valid_tweaksetting( keepalivetimeout => $_[0] ) },
);

has maxkeepaliverequests => (
    is      => "rw",
    default => sub { _get_default('maxkeepaliverequests') },
    trigger => sub { $_[0]->_set_is_dirty(1) },
    isa     => sub { return if !defined $_[0] || $_[0] == 0; _valid_nonnegative_int( $_[0] ) },    # see POD for why this is odd
);

has timeout => (
    is      => "rw",
    default => sub { _get_default('timeout') },
    trigger => sub { $_[0]->_set_is_dirty(1) },
    isa     => sub { _valid_tweaksetting( timeout => $_[0] ) },
);

has symlink_protect => (
    is      => "rw",
    default => sub { _get_default('symlink_protect') },
    trigger => sub { $_[0]->_set_is_dirty(1) },
    coerce  => \&_coerce_to_on_or_off,
    isa     => \&_valid_on_or_off,
);

###############
#### methods ##
###############

sub save {
    my ($self) = @_;

    my $trx = Cpanel::Transaction::File::JSON->new( path => $CONFPATH );
    $trx->set_data( $self->as_hr );

    $trx->save_pretty_canonical_or_die();
    $trx->close_or_die();

    $self->_set_is_dirty(0);
    Cpanel::EA4::Conf::Tiny::reset_memory_cache();

    return 1;
}

sub as_hr {
    my ($self) = @_;

    my $hr = { map { $_ => scalar( $self->$_ ) } @{ $self->conf_attrs } };
    $hr->{sslprotocol_list_str} = $self->sslprotocol_list_str;
    return $hr;
}

sub as_distiller_hr {
    my ($self) = @_;

    die "as_distiller_hr() called with unsaved changes\n" if $self->is_dirty;

    return Cpanel::EA4::Conf::Tiny::get_ea4_conf_distiller_hr();
}

sub save_from_hr {
    my ( $self, $hr ) = @_;

    $self->_set_hr( $hr, $hr );
    $self->save();

    return;
}

###############
#### helpers ##
###############

sub _set_hr {
    my ( $self, $hr, $args ) = @_;

    for my $attr ( @{ $self->conf_attrs } ) {
        next if !exists $hr->{$attr};

        next if $attr eq 'sslprotocol_list_str' && !exists $args->{sslprotocol_list_str};    # read-only
        next if $attr eq 'servername'           && !exists $args->{servername};              # read-only
        next if $attr eq 'serveradmin'          && !exists $args->{serveradmin};             # read-only

        if ( $attr eq 'local_attrs' ) {
            $self->_set_local_attrs( $hr->{$attr} );
        }
        else {
            $self->$attr( $hr->{$attr} );
        }
    }

    return;
}

my $defaults;

sub _ensure_defaults_loaded {
    $defaults ||= { Cpanel::EA4::Conf::Tiny::DEFAULTS_filled_in() } if ${^GLOBAL_PHASE} eq "RUN";
    return;
}

sub _get_default {
    my ($key) = @_;

    _ensure_defaults_loaded();
    if ( !exists $defaults->{$key} ) {
        die "“$key” is unknown\n";
    }

    return $defaults->{$key};
}

sub _coerce_to_on_or_off {
    my ($val) = @_;

    if ( !defined $val || ( $val ne 'On' && $val ne 'Off' ) ) {
        $val = $val ? 'On' : 'Off';
    }

    return $val;
}

sub _ensure_apache_ts {
    require Whostmgr::TweakSettings::Apache;
    Whostmgr::TweakSettings::Apache::init() if ${^GLOBAL_PHASE} eq "RUN";    # init() is idempotent
    return;
}

sub _valid_tweaksetting {
    my ( $key, $value ) = @_;

    _ensure_apache_ts();
    if ( !exists $Whostmgr::TweakSettings::Apache::Conf{$key} ) {
        die "“$key” does not exist in the WHM Tweak Setting data\n";
    }

    my $key_hr = $Whostmgr::TweakSettings::Apache::Conf{$key};

    if ( exists $key_hr->{'checkval'} ) {
        my $ret = $key_hr->{'checkval'}->($value);
        if ( $key eq 'root_options' ) {
            die $ret if ref($ret) ne 'ARRAY';
            return;
        }
        else {
            return if defined $ret;
        }
        die "“$value” is not a valid value for “$key”\n" if !defined $ret;
    }
    elsif ( exists $key_hr->{'options'} ) {
        if ( !grep { $value eq $_ } @{ $key_hr->{options} } ) {
            die "“$value” is not in the options list for “$key”\n";
        }
        return;
    }

    die "“$key” has no “options” or “checkval” in WHM, is it really a tweak setting?\n";
}

sub _valid_string {
    my ($value) = @_;

    die "cannot be undefined\n"       if !defined $value;
    die "cannot be empty\n"           if !length $value;
    die "cannot contain newlines\n"   if $value =~ m/\n/;
    die "cannot contain null bytes\n" if $value =~ m/\0/;

    return;
}

sub _valid_empty_string_or_nonnegative_int {
    my ($value) = @_;

    die "cannot be undefined\n" if !defined $value;
    return 1                    if $value eq "";

    _valid_nonnegative_int($value);

    return 1;
}

sub _valid_nonnegative_int {
    my ($value) = @_;

    die "cannot be undefined\n"                if !defined $value;
    die "must contain only ascii digits 0-9\n" if !length $value || $value =~ tr/0-9//c;    # negative sign is not valid so cool

    return 1;
}

sub _valid_on_or_off {
    my ($value) = @_;

    die "cannot be undefined\n"          if !defined $value;
    die "must be either “On” or “Off”\n" if $value ne "On" && $value ne "Off";

    return 1;
}

Sub::Defer::undefer_all();    # perlcc does not like defered sub routines, see ZC-5312 to see what happens without this. Created CPANEL-28402 to obviate the need for this

1;

__END__

=encoding utf8

=head1 NAME

Cpanel::EA4::Conf - configuration object for an EA4 conf file

=head1 SYNOPIS

   use Cpanel::EA4::Conf ();

   my $ea4cnf = Cpanel::EA4::Conf->instance();
   $ea4cnf->directoryindex($new_value);
   $ea4cnf->save;

Then in the template:

   [% ea4conf.directoryindex %]

=head1 DESCRIPTION

Cpanel::EA4::Conf consolidates general WebServer configuration options into
a single JSON file.

=head1 METHODS

=head2 new()

Returns a new EA4 Conf object. It can take a hash or hashref with keys of
anything in L</CONFIG ATTR METHODS> that is not read only. That may make sense to do something like:

     Cpanel::EA4::Conf->new(directoryindex => $new_value)->save;

Most of the time you likely want C<instance()> (with no args) instead of
C<new()> (w/ or w/out args).

=head2 instance()

Multiton version of C<new()>.

   sub foo {
       my $ec = Cpanel::EA4::Conf->instance();
       …
   }

   sub bar {
       my $ec = Cpanel::EA4::Conf->instance();
       …
   }

In that example both C<foo()> and C<bar()> get the same object. The first call
will set up the object and after that they all get the same one.

This is nice because you can avoid needing a global variable and doing gross
things like C<$ec ||= Cpanel::EA4::Conf->new;> everytime you want to use it.

=head2 warn_unsaved()

If warn_unsaved is enabled, you will be warned of unsaved changes when this
object goes out of scope.

Input/Return: 0 or 1

Example: 0

Default: 0

=head2 conf_attrs()

Returns an array ref of attributes that you can configure.

=head2 save()

Saves the current attribute values to the JSON file.

=head2 as_hr()

Takes no arguments. Returns the conf object as a hash reference.

=head2 as_distiller_hr()

Takes no arguments. Returns the conf object as the convoluted distiller hash
reference.

This is necessary to support older servers. This will be removed in v86 via
ZC-5276.

=head2 save_from_hr ($hr)

=over

=item C<$hr> A valid hash ref of attributes

=back

Will put each known item in the hash ref (see C<conf_attrs> for what is known)
into the object, and then saves the object.

=head2 is_dirty()

Takes no arguments. Returns true if any L</CONFIG ATTR METHODS> have set
values. Returns false otherwise.

    my $ea4cnf = Cpanel::EA4::Conf->instance();
    say $ea4cnf->is_dirty; # 0

    $ea4cnf->directoryindex($new_value);
    say $ea4cnf->is_dirty; # 1

    $ea4cnf->save;
    say $ea4cnf->is_dirty; # 0

=head2 local_attrs()

Take no arguments. Returns a hashref of local attributes.

This is useful for an admin who wants to use arbitrary config data beyond what
we know about and offer UIs to update.

This data can be managed via the object like this:

    my $e4c = Cpanel::EA4::Conf->instance();
    $e4c->local_attrs->{foo} = 42;
    $e4c->local_attrs->{bar} = "oh hai";
    delete $e4c->local_attrs->{baz};
    $e4c->save;

Then in their custom template they’d use

    [% ea4conf.local_attrs.foo %]

    [% ea4conf.local_attrs.bar %]

=head2 CONFIG ATTR METHODS

These are a set of getter and setter methods to access the various
configuration attributes.

To get the value:

    my $directoryindex = $conf_obj->directoryindex;

To set the value:

    $conf_obj->directoryindex ("index.js index.html");

Most of these attributes can be accessed or set in the same manner.
Exceptions are noted under the given item.

=over

=item directoryindex

A list of files to return when the url does not specify a file.

Input/Return: Space separated list.

Example: index.php index.php7 index.php5 index.perl

=item extendedstatus

Enable or disable the display of additional information about incoming
requests.

Input/Return: A string containing either On or Off.

Example: On

=item fileetag

Configures the file attributes that are used to create the ETag
response header field when the request is file based.

Input/Return: A string containing one of the following:
All None 'INode MTime' 'INode Size' 'MTime Size' INode MTime Size

Example: None

=item keepalive

Enables or disables persistent HTTP connections.

Input/Return: A string containing either On or Off.

Example: On

=item keepalivetimeout

The amount of time the server will wait for subsequent requests on a
persistent connection.

Input/Return: An integer >= 0, in seconds.

Example: 22

=item logformat_combined

The format of the log line.

Input/Return: A string

Example: %h %l %u %t \"%r\" %>s %b \"%{Referer}i\" \"%{User-Agent}i\"

=item logformat_common

The format of the log line.

Input/Return: A string

Example: %h %l %u %t \"%r\" %>s %b \"%{Referer}i\" \"%{User-Agent}i\"

=item loglevel

The verbosity of the logging, values like warn, info etc.

Input/Return: A string containing one of the following:
emerg alert crit error warn notice info debug

Example: emerg

=item maxclients

The limit on the number of simultaneous requests.

Input/Return: An integer >= 0

Example: 150

=item maxkeepaliverequests

The number of requests allowed on a persistent connection.

Input/Return: C<undef> or an integer >= 0

Example: 25

C<undef> and 0 mean unlimited.

C<undef> is allowed (and 0 coerced to C<undef>) for backwards compatibility w/ WHM’s Tweak Settings C<can_undef> behavior.

=item maxrequestsperchild

Limit on the number of requests that an individual child server process will
handle.

Input/Return: An integer >= 0

Example: 25

=item maxspareservers

The maximum number of idle child processes.

Input/Return: An integer >= 0

Example: 25

=item minspareservers

The minimum number of idle child processes.

Input/Return: An integer >= 0

Example: 25

=item rlimit_cpu_hard

Maximum number of cpu seconds a process may use.

Input/Return: An integer >= 0 or a blank string.

Example: 25

=item rlimit_cpu_soft

Maximum number of cpu seconds a process may use.

Input/Return: An integer >= 0 or a blank string.

Example: 25

=item rlimit_mem_hard

Maximum number of bytes a process may use.

Input/Return: An integer >= 0 or a blank string.

Example: 25

=item rlimit_mem_soft

Maximum number of bytes a process may use.

Input/Return: An integer >= 0 or a blank string.

Example: 25

=item root_options

A combination of the following: ExecCGI FollowSymLinks Includes IncludesNOEXEC
Indexes MultiViews SymLinksIfOwnerMatch.

Input/Return: Space separated list.

Example: ExecCGI FollowSymLinks Includes IncludesNOEXEC Indexes MultiViews SymLinksIfOwnerMatch

=item serverlimit

The maximum configured value for MaxClients for the lifetime of the process.

Input/Return: An integer >= 0

Example: 25

=item threadsperchild

The number of threads created by each child process.
This value is only valid if the MPM is threaded.

Input/Return: An integer >= 0

Example: 25

=item servername

This attribute is read only.

The name to use for the default server name.

=item serveradmin

This attribute is read only.

The email address of the server administrator.

=item serversignature

This “signature” is the trailing footer line under server-generated
documents (error messages, information pages, etc).

Input/Return: A string containing On, Off or Email.

Example: On

=item servertokens

This controls whether a “Server” response header field is sent back to
clients, and if so what level of detail is included.

Input/Return: A string containing one of the following:
ProductOnly Minimal OS Full

Example: ProductOnly

=item sslciphersuite

A colon separated cipher-spec strings.

Input/Return: A string list of ciphers separated by colons.

Example: ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305

=item sslprotocol

A space separated string of protocol specifications.

Input/Return: A string containing protocols separated by spaces.

Example: TLSv1.2 TLSv1.3

=item sslprotocol_list_str

This attribute is read only.

A space separated string of protocol names based on the expression that is C<sslprotocol>.

For example, if the know protocols are C<FOO>, C<BAR>, and C<BAZ>; if C<sslprotocol> is C<all -BAR>, then C<sslprotocol_list_str> will return C<FOO BAZ>.

=item sslusestapling

Enable or disable OCSP stapling. If enabled (and requested by the client), the server
will include an OCSP response for its own certificate in the TLS handshake.

Input/Return: A string containing either On or Off.

Example: On

=item startservers

The number of child servers that are created on startup.

Input/Return: An integer >= 0

Example: 25

=item symlink_protect

Enables or disables symlink protection in order to reduce the impact of
race conditions if you enable the FollowSymlinks and SymLinksIfOwnerMatch
Apache directives.

Input/Return: A string containing On or Off.

Example: Off

=item timeout

Amount of time to wait before failing a request.

Input/Return: An integer > 3 and < 604800

Example: 25

=item traceenable

Sets the behavior of TRACE requests.

Input/Return: A string containing On, Off or Extended.

Example: Off

=back

=head1 ADDING A NEW CONFIG ATTR METHOD

=over

=item Add the C<has>

You can use existing ones as a guide. Also see L<Moo> for more info.

=item Add the POD

=item Add the test

At the very least add an C<it_should_behave_like> of either
“Cpanel-EA4-Conf config items” or “Read-Only Cpanel-EA4-Conf config items”
in t/small/.spec_helpers/Cpanel-EA4-Conf.pl

=item Add it to C<Cpanel::EA4::Conf::Tiny::DEFAULTS> (see C<servername> as an example of how to a readonly/dynamic attr)

=item Add it to C<Cpanel::EA4::Conf::Tiny::get_ea4_conf_distiller_hr()>’s data structure

This involves determining what it looked like because not all items were the same structure.

=item Add it to C<_get_expected_distiller_hr()>’s hash

That is in t/small/.spec_helpers/Cpanel-EA4-Conf.pl.

=item If it is Read-Only:

=over

=item add a C<next> for it in C<_set_hr>

=item add it to L<Cpanel::EA4::Conf::Tiny::DEFAULTS_filled_in()> (see C<servername> as an example)

=item add a C<next> for it in C<_import_and_archive_distiller_data()> in L<scripts/rebuildhttpdconf>

=back

=back
