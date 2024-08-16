package Cpanel::PasswdStrength::Check;

# cpanel - Cpanel/PasswdStrength/Check.pm          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Cpanel::LoadFile         ();
use Cpanel::StringFunc::Case ();

## no critic (RequireUseWarnings)

our $VERSION = '1.10';

use constant MAX_STRENGTH      => 100;
use constant ENTROPY_THRESHOLD => 70;

my @bad_passwords;

# These three types of virtual accounts have had their password strength requirements
# unified. The strengths for these services will no longer be independently configurable
# in WHM.
my %app_mapping = (
    'pop'     => 'virtual',
    'ftp'     => 'virtual',
    'webdisk' => 'virtual',
);

#Returns undef/empty if invalid.
sub valid_strength {
    return if $_[0] =~ m{\D};

    if ( !$_[0] ) {
        return 0;
    }
    elsif ( $_[0] > 0 && $_[0] <= MAX_STRENGTH() ) {
        return $_[0];
    }

    return;
}

sub get_required_strength {
    my $app = shift;
    return 0 if !$app;

    $app = $app_mapping{$app} ? $app_mapping{$app} : $app;

    my $required_strength;
    if ( ( tied %Cpanel::CONF || scalar keys %Cpanel::CONF ) ) {
        $required_strength =
          exists $Cpanel::CONF{ 'minpwstrength_' . $app }
          ? int $Cpanel::CONF{ 'minpwstrength_' . $app }
          : ( exists $Cpanel::CONF{'minpwstrength'} ? int $Cpanel::CONF{'minpwstrength'} : 0 );
    }
    else {
        require Cpanel::Config::LoadCpConf;
        my $cpconf_ref = Cpanel::Config::LoadCpConf::loadcpconf_not_copy();
        $required_strength =
          exists $cpconf_ref->{ 'minpwstrength_' . $app }
          ? int $cpconf_ref->{ 'minpwstrength_' . $app }
          : ( exists $cpconf_ref->{'minpwstrength'} ? int $cpconf_ref->{'minpwstrength'} : 0 );
    }

    return $required_strength;
}

#named opts are:
#   app     - the application (e.g., 'mysql')
#   pw      - the password
#
sub verify_or_die {
    my %OPTS = @_;

    die "Invalid call!" if !$OPTS{'app'} || !defined $OPTS{'pw'};

    if ( !check_password_strength(%OPTS) ) {
        eval 'require Cpanel::Exception;' or die "Failed to load Cpanel::Exception: $@";
        die 'Cpanel::Exception'->can('create')->( 'PasswordIsTooWeak', { application => $OPTS{'app'} } );
    }

    return 1;
}

sub check_password_strength {
    my %OPTS = @_;
    return ( int( get_required_strength( $OPTS{'app'} ) ) > int( get_password_strength( $OPTS{'pw'} ) ) ? 0 : 1 );
}

my $_bad_passwords;

sub get_password_strength {    ## no critic (ProhibitExcessComplexity)
    my ($password) = @_;

    # Security policies require this to be 0.
    return 0 unless length $password;

    if ( length($password) < 4 ) {
        return 1;
    }

    require Crypt::Cracklib;
    return 1 if !Crypt::Cracklib::check($password);

    $_bad_passwords ||= get_bad_passwords_ref();
    my $lc_password = Cpanel::StringFunc::Case::ToLower($password);
    if ( grep { $lc_password eq $_ } @{$_bad_passwords} ) {
        return 1;
    }

    my $arabic        = 0x00000001;
    my $a_through_f   = 0x00000002;
    my $g_through_z   = 0x00000004;
    my $A_through_F   = 0x00000008;
    my $G_through_Z   = 0x00000010;
    my $symbols       = 0x00000020;
    my $other_symbols = 0x00000040;
    my $space         = 0x00000080;

    my $used                = 0x00000000;
    my @password_characters = split( //, $password );
    my $last_character;
    my $different_count = 0;
    my $pattern_count   = 0;
    foreach my $character (@password_characters) {
        my $character_codepoint = unpack( 'C', $character );
        my $below_character     = pack( 'C', $character_codepoint - 1 );
        my $above_character     = pack( 'C', $character_codepoint + 1 );
        if ( !$last_character || ( $last_character ne $character && $last_character ne $below_character && $last_character ne $above_character ) ) {
            $different_count++;
        }
        else {
            $pattern_count++;
        }
        $last_character = $character;
        if    ( $character =~ tr/0-9// )                           { $used |= $arabic; }
        elsif ( $character =~ tr/a-f// )                           { $used |= $a_through_f; }
        elsif ( $character =~ tr/g-z// )                           { $used |= ( $a_through_f | $g_through_z ); }
        elsif ( $character =~ tr/A-F// )                           { $used |= $A_through_F; }
        elsif ( $character =~ tr/G-Z// )                           { $used |= ( $A_through_F | $G_through_Z ); }
        elsif ( $character =~ tr/!$%&\(\)\*\+,-.\/:<=>\?`{\|}~// ) { $used |= $symbols; }
        elsif ( $character =~ tr /"#';// )                         { $used |= $other_symbols; }
        elsif ( $character =~ tr / // )                            { $used |= $space; }
        else                                                       { $used = 0xFFFFFFFF; }
    }
    if ( $used & $a_through_f && !$used & $arabic ) { $used |= $g_through_z }
    if ( $used & $A_through_F && !$used & $arabic ) { $used |= $G_through_Z }

    my $symbol_count = 0;
    if ( $used & $arabic )        { $symbol_count += 10 }
    if ( $used & $a_through_f )   { $symbol_count += 6 }
    if ( $used & $g_through_z )   { $symbol_count += 20 }
    if ( $used & $A_through_F )   { $symbol_count += 6 }
    if ( $used & $G_through_Z )   { $symbol_count += 20 }
    if ( $used & $symbols )       { $symbol_count += 22 }
    if ( $used & $other_symbols ) { $symbol_count += 4 }
    if ( $used & $space )         { $symbol_count += 1 }

    my $entropy = $different_count * ( log($symbol_count) / log(2) );

    # the pattern bits add entropy too, but there's only 3 choices: equal, above, or below.
    $entropy += $pattern_count * ( log(3) / log(2) );

    # 76 is just below 6.39 * 12, which corresponds with our policy of
    # a 12 digit password using arabic digits, both cases of the alphabet, and symbols.
    if ( $entropy > ENTROPY_THRESHOLD() ) {
        return MAX_STRENGTH();
    }
    else {
        return int MAX_STRENGTH() * ( $entropy / ENTROPY_THRESHOLD() );
    }
}

sub get_bad_passwords_ref {
    return \@bad_passwords if @bad_passwords;
    foreach my $list ( '/etc/bad_passwords_list', '/usr/local/cpanel/etc/bad_passwords_list' ) {
        push @bad_passwords, grep { tr{ \t}{}c } split( m{\s}, Cpanel::LoadFile::load_if_exists($list) // '' );
    }
    return \@bad_passwords;
}

sub _count_case_insenstive_occurrences_in_string {
    my ( $string, $array_ref ) = @_;

    # check against the worst password's list (case insensitive)
    my $regex = '(' . join( '|', map { quotemeta($_) } @{$array_ref} ) . ')';
    my $count = () = $string =~ /$regex/gi;
    return $count;
}

1;
__END__

=pod

=head1 NAME

Cpanel::PasswordStrength::Check - Password strength checking

=head1 VERSION

This document refers to Cpanel::PasswordStrength::Check version 1.10

=head1 SYNOPSIS

    use Cpanel::PasswordStrength::Check ();

    # obtain the strength of a password
    my $strength = Cpanel::PasswordStrength::Check::get_password_strength($password);

=head1 DESCRIPTION

Cpanel::PasswordStrength::Check provides access to the password strength
algorithm, and related utilites that indicate if the password strength is
sufficient for access various facilities.

=head1 METHODS

=head2 B<$strength = Cpanel::PasswordStrength::Check::get_password_strength($password)>

Gets the password strength for a particular password.

Passwords which are part of a known dictionary will return a strength of zero.

Passwords which pass the dictionary checks are scanned to determine if they contain
characters that are found within gropus (digits, symbols, lower case, etc.).  Once
the number of groups the password was selected from is determined, the symbols
within those groups are counted and the entropy per character is computed (and
added to the total).

Characters that participate in in-password patterns have a different contribution
to entropy.  The number of characters that could participate in the pattern are
counted and the entropy per pattern character is computed (and added to the
total).

The total entropy is then compared to the minimum desired entropy, computing
a percentage of acceptance, capped at 100%.

=over 4

=item B<$password>

The password that is to have its strength computed.

=back

=head3 B<Returns>

=over 4

=item B<$strength>

A number indicating the strength of the password, ranging from zero to one hundred.

=back

=head1 CONFIGURATION AND ENVIRONMENT

This module requires a Linux operating system with cracklib-check installed.

=head1 DEPENDENCIES

This module uses:

=over 8

=item cracklib-check

Used for checking passwords against the cracklib dictionaries.  This command line
program is typically already part of a minimal install on a RedHat or similar
Linux operating system.

=back

=head1 INCOMPATIBILITIES

No known incompatibilities.

=head1 BUGS AND LIMITATIONS

Currently the number of patterns is small, and only contain "one above, repeat, and
one below" checks.  It is important to scan the password to verify it is somewhat
random, as the entropy based strength measurement will over report a password's
strength if it is based on a pattern.  With this in mind, patterned passwords only
provide easier attack surfaces if the attacker uses tools that guess along pattern
rules.

The 100% strength level is set against a static entropy guideline.  As the desired
entropy for security changes yearly, we should probably remove the percentage based
reporting with a desired entropy, so customers can dial in the new desired entropy
instead of being capped at 100% of a non-configurable entropy.  An effort like this
would require work on the generator so configuring the desired entropy would also
configure the generator to generate passwords that pass the desired entropy goals.
