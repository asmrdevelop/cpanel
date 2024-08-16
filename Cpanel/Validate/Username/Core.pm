package Cpanel::Validate::Username::Core;

# cpanel - Cpanel/Validate/Username/Core.pm        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

# DO NOT ADD DEPS or foreign pkgacct will fail
use Cpanel::Validate::Username::Mode ();
use Cpanel::ArrayFunc::Uniq          ();
use Cpanel::LoadFile                 ();
################################################################################
#
# This module contains the core functionality of username validation that is
# shared by both the cpanel-whm and pkgacct repositories.  This module MUST
# work in both repositories without any modifications (i.e. they should be
# identical).  As such, we should not directly rely on any modules that are not
# available in both repositories.  The Cpanel::Validate::Username::Mode module
# provides an interface for abstracting out differences between the two repos;
# please put repo-specific dependencies there.
#
################################################################################

our $MAX_LENGTH                 = 16;                    #Constrained by MySQL
our $MAX_SYSTEM_USERNAME_LENGTH = 31;
our $ETC_ALIASES_PATH           = '/etc/aliases';
our $ETC_LOCALALIASES_PATH      = '/etc/localaliases';

my @_list_reserved_usernames;

sub list_reserved_usernames {
    return @_list_reserved_usernames if @_list_reserved_usernames;
    my @names = qw(
      abrt
      all
      clamav
      cpanel-ccs
      cpeasyapache
      cpses
      cptkt
      cphulkd
      cpwebcalls
      dbus
      dirs
      dnsadmin
      dovecot
      eximstats
      files
      ftpxferlog
      haldaemon
      information_schema
      mailman
      modsec
      munin
      mydns
      nobody
      performance_schema
      postgres
      postmaster
      proftpd
      root
      roundcube
      shadow
      spamassassin
      ssl
      sys
      system
      tcpdump
      tmp
      tomcat
      toor
      virtfs
      virtual
      webmaster
      whmxfer
      _lock
    );
    push @names, aliases();
    push @names, Cpanel::Validate::Username::Mode::additional_reserved_usernames();
    return ( @_list_reserved_usernames = Cpanel::ArrayFunc::Uniq::uniq(@names) );
}

sub reserved_username_prefixes {
    return qw(test
      passwd.
      cpmydns
      cpanel
      mydns
      pg_toast
      pg_temp
      cpses
      cptkt
      cpbackup);
}

sub reserved_username_suffixes {
    return qw(
      .lock
      .cache
      .yaml
      .json
      .db
      assword
    );
}

# These must work in JavaScript as well as Perl.
sub list_reserved_username_patterns {
    return (
        list_reserved_username_regexes(),
        ( map { '^' . quotemeta($_) } reserved_username_prefixes() ),
        ( map { quotemeta($_) . '$' } reserved_username_suffixes() )
    );
}

sub list_reserved_username_regexes {
    return qw(
      ^[-._0-9]+$
    );
}

#Validates that a string is a valid SYSTEM username under any circumstances.
sub get_system_username_regexp_str {
    return '^' . _regexp_lead() . "[-._A-Za-z0-9]{1,$MAX_SYSTEM_USERNAME_LENGTH}\$";
}

#Validates that a string is a valid cPanel username under any circumstances.
sub get_regexp_str {
    return '^' . _regexp_lead() . "[-._a-z0-9]{1,$MAX_LENGTH}\$";
}

sub _regexp_lead {
    return Cpanel::Validate::Username::Mode::allows_leading_digits() ? '(?![-.])' : '(?![-.0-9])';
}

sub is_valid_system_username {
    my ($user) = @_;
    return if !defined $user;

    my $regexp = get_system_username_regexp_str();

    $regexp = _apply_perl_boundary($regexp);

    return $user =~ m{$regexp}o;
}

#for validating transferred as well as new account names
sub is_valid {
    my ($user) = @_;
    return if !defined $user;

    my $regexp = get_regexp_str();

    $regexp = _apply_perl_boundary($regexp);

    return $user =~ m{$regexp}o;
}

sub normalize {
    my ($name) = @_;
    return unless defined $name;
    $name =~ s/^\s+//;
    $name =~ s/\s+$//;
    $name =~ tr/A-Z/a-z/;
    return $name;
}

sub scrub {
    my ($name) = @_;
    return unless defined $name;

    $name = normalize($name);
    if ( Cpanel::Validate::Username::Mode::in_transfer_mode() ) {
        $name =~ tr/-a-z0-9._//cd;
    }
    else {
        $name =~ tr/a-z0-9._//cd;
    }

    substr( $name, 0, 1, '' ) while index( $name, '.' ) == 0;
    $name =~ s/^\d+// unless Cpanel::Validate::Username::Mode::allows_leading_digits();

    #Truncate overly-long usernames to $MAX_LENGTH bytes.
    if ( length $name > $MAX_LENGTH ) {
        substr( $name, $MAX_LENGTH ) = q{};
    }

    return $name;
}

sub reserved_username_check {
    my ($user) = @_;

    return   if !$user;
    return 1 if grep { $_ eq $user } list_reserved_usernames();
    return 1 if grep { rindex( $user, $_, 0 ) == 0 } reserved_username_prefixes();
    return 1 if grep { index( $user, $_, length($user) - length($_) ) != -1 } reserved_username_suffixes();
    return 1 if grep { $user =~ m{$_} } list_reserved_username_regexes();
    return;
}

sub aliases {
    my @reserved_names;

    foreach my $file ( $ETC_ALIASES_PATH, $ETC_LOCALALIASES_PATH ) {
        next if ( !-f $file || !-r _ );

        my ( $name, $line );
        for $line ( split m<\n+>, Cpanel::LoadFile::load($file) ) {
            $name = ( split /:/, $line )[0];
            next if !length $name || $name =~ tr< :#\t><>;

            push @reserved_names, $name;
        }
    }
    return @reserved_names;
}

sub _apply_perl_boundary {
    $_[0] =~ s{^\^}{\\A};
    $_[0] =~ s{\$$}{\\z};
    return $_[0];
}

1;
