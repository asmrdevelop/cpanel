package Cpanel::PwCache::Build;

# cpanel - Cpanel/PwCache/Build.pm                    Copyright 2022 cPanel L.L.C
#                                                            All rights reserved.
# copyright@cpanel.net                                          http://cpanel.net
# This code is subject to the cPanel license.  Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Debug                        ();
use Cpanel::JSON::FailOK                 ();
use Cpanel::FileUtils::Write::JSON::Lazy ();
use Cpanel::PwCache::Helpers             ();
use Cpanel::PwCache::Cache               ();
use Cpanel::LoadFile::ReadFast           ();

=encoding utf-8

=head1 NAME

Cpanel::PwCache::Build - Tools for building, caching, and reading the system password files.

=head1 SYNOPSIS

    use Cpanel::PwCache::Build ();

    my $pwcache_ref = Cpanel::PwCache::Build::fetch_pwcache();

=cut

my ( $MIN_FIELDS_FOR_VALID_ENTRY, $pwcache_has_uid_cache ) = ( 0, 6 );

sub pwmksafecache {
    return if Cpanel::PwCache::Cache::is_safe();
    my $pwcache_ref = Cpanel::PwCache::Cache::get_cache();

    $pwcache_ref->{$_}{'contents'}->[1] = 'x' for keys %{$pwcache_ref};

    Cpanel::PwCache::Cache::is_safe(1);

    return;
}

sub pwclearcache {    # also known as clear_this_process_cache
    $pwcache_has_uid_cache = undef;

    Cpanel::PwCache::Cache::clear();

    return;
}

sub init_pwcache {
    Cpanel::PwCache::Cache::is_safe(0);
    return _build_pwcache();
}

sub init_passwdless_pwcache {
    return _build_pwcache( 'nopasswd' => 1 );
}

sub fetch_pwcache {
    init_passwdless_pwcache() unless pwcache_is_initted();
    my $pwcache_ref = Cpanel::PwCache::Cache::get_cache();
    if ( scalar keys %$pwcache_ref < 3 ) {
        die "The password cache unexpectedly had less than 3 entries";
    }
    return [ map { $pwcache_ref->{$_}->{'contents'} } grep { substr( $_, 0, 1 ) eq '0' } keys %{$pwcache_ref} ];
}

sub _write_json_cache {
    my ($cache_file) = @_;
    if ( !Cpanel::PwCache::Helpers::istied() && exists $INC{'Cpanel/JSON.pm'} ) {
        my $pwcache_ref = Cpanel::PwCache::Cache::get_cache();
        if ( !ref $pwcache_ref || scalar keys %$pwcache_ref < 3 ) {
            die "The system failed build the password cache";
        }

        # This used to lock, however locking did nothing to avoid a race condition
        # that is already handled in the load function so it was removed.
        Cpanel::FileUtils::Write::JSON::Lazy::write_file( $cache_file, $pwcache_ref, 0600 );
    }
    return;
}

sub _write_tied_cache {
    my ( $crypted_passwd_ref, $passwdmtime, $hpasswdmtime ) = @_;
    my $SYSTEM_CONF_DIR = Cpanel::PwCache::Helpers::default_conf_dir();
    local $!;
    if ( open( my $pwcache_passwd_fh, '<:stdio', "$SYSTEM_CONF_DIR/passwd" ) ) {
        local $/;
        my $pwcache_ref = Cpanel::PwCache::Cache::get_cache();
        my $data        = '';
        Cpanel::LoadFile::ReadFast::read_all_fast( $pwcache_passwd_fh, $data );
        die "The file “$SYSTEM_CONF_DIR/passwd” was unexpectedly empty" if !length $data;
        my @fields;
        my $skip_uid_cache = Cpanel::PwCache::Helpers::skip_uid_cache();

        foreach my $line ( split( /\n/, $data ) ) {
            next unless length $line;
            @fields = split( /:/, $line );
            next if scalar @fields < $MIN_FIELDS_FOR_VALID_ENTRY || $fields[0] =~ tr/[A-Z][a-z][0-9]._-//c;
            $pwcache_ref->{ '0:' . $fields[0] } = {
                'cachetime'  => $passwdmtime,
                'hcachetime' => $hpasswdmtime,
                'contents'   => [ $fields[0], $crypted_passwd_ref->{ $fields[0] } || $fields[1], $fields[2], $fields[3], '', '', $fields[4], $fields[5], $fields[6], -1, -1, $passwdmtime, $hpasswdmtime ]
            };
            next if $skip_uid_cache || !defined $fields[2] || exists $pwcache_ref->{ '2:' . $fields[2] };
            $pwcache_ref->{ '2:' . $fields[2] } = $pwcache_ref->{ '0:' . $fields[0] };
        }
        close($pwcache_passwd_fh);
    }
    else {
        die "The system failed to read $SYSTEM_CONF_DIR/passwd because of an error: $!";
    }
    return;
}

sub _cache_ref_is_valid {
    my ( $cache_ref, $passwdmtime, $hpasswdmtime ) = @_;
    my @keys = qw/0:root 0:cpanel 0:bin/;
    return
         $cache_ref
      && ( scalar keys %{$cache_ref} ) > 2
      && scalar @keys == grep {    #
             $cache_ref->{$_}->{'hcachetime'}
          && $cache_ref->{$_}->{'hcachetime'} == $hpasswdmtime
          && $cache_ref->{$_}->{'cachetime'}
          && $cache_ref->{$_}->{'cachetime'} == $passwdmtime
      } @keys;
}

sub _build_pwcache {
    my %OPTS = @_;

    if ( $INC{'B/C.pm'} ) {
        Cpanel::PwCache::Helpers::confess("Cpanel::PwCache::Build::_build_pwcache cannot be run under B::C (see case 162857)");
    }

    my $SYSTEM_CONF_DIR = Cpanel::PwCache::Helpers::default_conf_dir();

    my ( $cache_file, $passwdmtime, $cache_file_mtime, $crypted_passwd_ref, $crypted_passwd_file, $hpasswdmtime ) = ( "$SYSTEM_CONF_DIR/passwd.cache", ( stat("$SYSTEM_CONF_DIR/passwd") )[9] );

    if ( $OPTS{'nopasswd'} ) {

        # We still need to check the shadow file because getpwnam will explicitly check this anyways
        $hpasswdmtime = ( stat("$SYSTEM_CONF_DIR/shadow") )[9];
        $cache_file   = "$SYSTEM_CONF_DIR/passwd" . ( Cpanel::PwCache::Helpers::skip_uid_cache() ? '.nouids' : '' ) . '.cache';
    }
    elsif ( -r "$SYSTEM_CONF_DIR/shadow" ) {
        Cpanel::PwCache::Cache::is_safe(0);
        $hpasswdmtime        = ( stat(_) )[9];
        $crypted_passwd_file = "$SYSTEM_CONF_DIR/shadow";
        $cache_file          = "$SYSTEM_CONF_DIR/shadow" . ( Cpanel::PwCache::Helpers::skip_uid_cache() ? '.nouids' : '' ) . '.cache';
    }
    else {
        $hpasswdmtime = 0;
    }

    if ( !Cpanel::PwCache::Helpers::istied() && exists $INC{'Cpanel/JSON.pm'} ) {
        if ( open( my $cache_fh, '<:stdio', $cache_file ) ) {
            my $cache_file_mtime = ( stat($cache_fh) )[9] || 0;
            if ( $cache_file_mtime > $hpasswdmtime && $cache_file_mtime > $passwdmtime ) {
                my $cache_ref = Cpanel::JSON::FailOK::LoadFile($cache_fh);
                Cpanel::Debug::log_debug("[read pwcache from $cache_file]") if ( $Cpanel::Debug::level > 3 );
                if ( _cache_ref_is_valid( $cache_ref, $passwdmtime, $hpasswdmtime ) ) {
                    Cpanel::Debug::log_debug("[validated pwcache from $cache_file]") if ( $Cpanel::Debug::level > 3 );
                    my $memory_pwcache_ref = Cpanel::PwCache::Cache::get_cache();
                    @{$cache_ref}{ keys %$memory_pwcache_ref } = values %$memory_pwcache_ref;
                    Cpanel::PwCache::Cache::replace($cache_ref);
                    $Cpanel::PwCache::Cache::pwcache_inited = ( $OPTS{'nopasswd'} ? 1 : 2 );
                    return;
                }

            }
        }
    }

    if ($crypted_passwd_file) { $crypted_passwd_ref = _load_pws($crypted_passwd_file); }
    $Cpanel::PwCache::Cache::pwcache_inited = ( $OPTS{'nopasswd'}                          ? 1 : 2 );
    $pwcache_has_uid_cache                  = ( Cpanel::PwCache::Helpers::skip_uid_cache() ? 0 : 1 );

    _write_tied_cache( $crypted_passwd_ref, $passwdmtime, $hpasswdmtime );
    _write_json_cache($cache_file) if $> == 0;

    return 1;
}

sub pwcache_is_initted {
    return ( $Cpanel::PwCache::Cache::pwcache_inited ? $Cpanel::PwCache::Cache::pwcache_inited : 0 );
}

sub _load_pws {
    my $lookup_file = shift;

    if ( $INC{'B/C.pm'} ) {
        Cpanel::PwCache::Helpers::confess("Cpanel::PwCache::Build::_load_pws cannot be run under B::C (see case 162857)");
    }

    my %PW;
    if ( open my $lookup_fh, '<:stdio', $lookup_file ) {
        my $data = '';
        Cpanel::LoadFile::ReadFast::read_all_fast( $lookup_fh, $data );
        die "The file “$lookup_file” was unexpectedly empty" if !length $data;
        %PW = map { ( split(/:/) )[ 0, 1 ] } split( /\n/, $data );
        if ( index( $data, '#' ) > -1 ) {
            delete @PW{ '', grep { index( $_, '#' ) == 0 } keys %PW };
        }
        else {
            delete $PW{''};
        }
        close $lookup_fh;
    }
    return \%PW;
}

1;
