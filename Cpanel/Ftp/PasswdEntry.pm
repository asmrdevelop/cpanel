package Cpanel::Ftp::PasswdEntry;

# cpanel - Cpanel/Ftp/PasswdEntry.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#----------------------------------------------------------------------
# This class parses and serializes a line from an FTP passwd file.
#
# Instantiate with one of three arguments:
#   - scalar ref (parsed as a line entry)
#   - array ref (interpreted via @ORDER below)
#   - hash ref (keyed with values of @ORDER below)
#
# This class's constructor will die() on errors, so always wrap in eval {}.
#
# Accessor methods are defined as @ORDER members.
#----------------------------------------------------------------------

use strict;

use Cpanel::Validate::VirtualUsername ();
use Cpanel::Validate::PwFileEntry     ();

#This is the order in which these items appear in a passwd file line.
my @ORDER = qw(
  ftpuser
  cryptftppass
  ouid
  ogid
  owner
  homedir
  shell
);

# For FTP username validation:
# We may not know the domain for the user here, nor do we need to look it up. In the case
# of a user stored without a domain, just validate with the shortest domain a person could
# possibly have.
my $DUMMY_DOMAIN = 'a.a';

#----------------------------------------------------------------------
# Per JNK, it is necessary to write these out manually in order to
# reap optimization benefits from perlcc.
#----------------------------------------------------------------------

my %ATTRIBUTE_INDEX = map { $ORDER[$_] => $_ } ( 0 .. $#ORDER );

sub migrate_cpusername {
    my ( $self, $old_cpuser, $new_cpuser ) = @_;

    my $ftpuser = $self->ftpuser();

    if ( $ftpuser eq $old_cpuser ) {
        $self->set_ftpuser($new_cpuser);
    }
    elsif ( $ftpuser eq $old_cpuser . "_logs" ) {
        $self->set_ftpuser( $new_cpuser . "_logs" );
    }

    return 1;
}

sub ftpuser {
    my ($self) = @_;
    return $self->[ $ATTRIBUTE_INDEX{'ftpuser'} ];
}

sub set_ftpuser {
    my ( $self, $value ) = @_;
    Cpanel::Validate::PwFileEntry::validate_or_die($value);

    _validate_ftp_username_as_virtual_username($value);

    return $self->[ $ATTRIBUTE_INDEX{'ftpuser'} ] = $value;
}

sub cryptftppass {
    my ($self) = @_;
    return $self->[ $ATTRIBUTE_INDEX{'cryptftppass'} ];
}

sub set_cryptftppass {
    my ( $self, $value ) = @_;
    Cpanel::Validate::PwFileEntry::validate_or_die($value);
    return $self->[ $ATTRIBUTE_INDEX{'cryptftppass'} ] = $value;
}

sub ouid {
    my ($self) = @_;
    return $self->[ $ATTRIBUTE_INDEX{'ouid'} ];
}

sub set_ouid {
    my ( $self, $value ) = @_;
    Cpanel::Validate::PwFileEntry::validate_or_die($value);
    return $self->[ $ATTRIBUTE_INDEX{'ouid'} ] = $value;
}

sub ogid {
    my ($self) = @_;
    return $self->[ $ATTRIBUTE_INDEX{'ogid'} ];
}

sub set_ogid {
    my ( $self, $value ) = @_;
    Cpanel::Validate::PwFileEntry::validate_or_die($value);
    return $self->[ $ATTRIBUTE_INDEX{'ogid'} ] = $value;
}

sub owner {
    my ($self) = @_;
    return $self->[ $ATTRIBUTE_INDEX{'owner'} ];
}

sub set_owner {
    my ( $self, $value ) = @_;
    Cpanel::Validate::PwFileEntry::validate_or_die($value);
    return $self->[ $ATTRIBUTE_INDEX{'owner'} ] = $value;
}

sub homedir {
    my ($self) = @_;
    return $self->[ $ATTRIBUTE_INDEX{'homedir'} ];
}

sub set_homedir {
    my ( $self, $value ) = @_;
    Cpanel::Validate::PwFileEntry::validate_or_die($value);
    return $self->[ $ATTRIBUTE_INDEX{'homedir'} ] = $value;
}

sub shell {
    my ($self) = @_;
    return $self->[ $ATTRIBUTE_INDEX{'shell'} ];
}

sub set_shell {
    my ( $self, $value ) = @_;
    Cpanel::Validate::PwFileEntry::validate_or_die($value);
    return $self->[ $ATTRIBUTE_INDEX{'shell'} ] = $value;
}

#END written-out getters and setters
#----------------------------------------------------------------------

my $PACKAGE = __PACKAGE__;

my $DEFAULT_SHELL = '/bin/ftpsh';

my %CAN_BE_EMPTY = map { $_ => undef } qw(
  owner
  cryptftppass
);    # cryptftppass is always empty for ftp / anonftp

sub _parse_line {
    my ( $self, $line_sr ) = @_;

    @$self = split m{:}, $$line_sr;

    return;
}

sub _parse_array {
    my ( $self, $line_ar ) = @_;

    @$self = @$line_ar;

    return;
}

sub _parse_hash {
    my ( $self, $line_hr ) = @_;

    @$self = map { $line_hr->{$_} } @ORDER;

    return;
}

my %parser = (
    SCALAR => '_parse_line',
    ARRAY  => '_parse_array',
    HASH   => '_parse_hash',
);

sub _validate {
    my ($self) = @_;

    $self->_do_shell_fallback();

    for my $i ( 0 .. $#ORDER ) {
        if ( !length $self->[$i] && !exists $CAN_BE_EMPTY{ $ORDER[$i] } ) {
            die "New $PACKAGE instance is missing “$ORDER[$i]” value!\n";
        }
    }

    my $ftpuser = $self->ftpuser();

    _validate_ftp_username_as_virtual_username($ftpuser);

    return 1;
}

sub _do_shell_fallback {
    my ($self) = @_;

    if ( !length $self->shell() ) {
        $self->set_shell($DEFAULT_SHELL);
    }

    return;
}

sub new {
    my ( $class, $line_ref ) = @_;

    my $self = bless [], $class;

    if ( defined $line_ref ) {
        if ( !ref $line_ref ) {
            $line_ref = \"$line_ref";
        }

        my $parser_name = $parser{ ref $line_ref };
        die "Invalid argument to $PACKAGE: $line_ref" if !$parser_name;

        $self->$parser_name($line_ref);

        $self->_validate();
    }
    else {
        $self->_do_shell_fallback();
    }

    return $self;
}

sub to_string {
    my ($self) = @_;

    return join q{:}, map { defined( $self->[$_] ) ? $self->[$_] : q{} } ( 0 .. $#ORDER );
}

sub _validate_ftp_username_as_virtual_username {
    my ($ftpuser) = @_;
    $ftpuser .= '@' . $DUMMY_DOMAIN if $ftpuser !~ tr/@//;
    return Cpanel::Validate::VirtualUsername::validate_or_die($ftpuser);
}

1;
