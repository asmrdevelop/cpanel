package Cpanel::Caller;

# cpanel - Cpanel/Caller.pm                        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#----------------------------------------------------------------------
# A "nice" interface to caller().
#
# There is no OO here; just call methods statically, passing in the #
# of stack frames to go back -- i.e., the same argument that you'd give to
# caller().
#
# (See also CPAN Perl6::Caller.)
#----------------------------------------------------------------------

use strict;

my %PROPERTY_INDEX;

sub _get {
    my ( $property, $frames_back_count ) = @_;

    if ( !%PROPERTY_INDEX ) {
        my @PROPERTIES_ORDER = qw(
          package
          filename
          line
          subroutine
          hasargs
          wantarray
          evaltext
          is_require

          hints__NOT_USED__
          bitmask__NOT_USED__

          hinthash
        );

        %PROPERTY_INDEX = map { $PROPERTIES_ORDER[$_] => $_ } ( 0 .. $#PROPERTIES_ORDER );
    }

    $frames_back_count ||= 0;
    $frames_back_count += 2;

    return scalar( ( caller $frames_back_count )[ $PROPERTY_INDEX{$property} ] );
}

#----------------------------------------------------------------------

#Each of these accepts the # of stack frames to go back
#.. i.e., the same argument you'd give to caller().
#
#See "perldoc -f caller" for what each of these does.
#
sub evaltext   { return _get( 'evaltext',   @_ ) }
sub filename   { return _get( 'filename',   @_ ) }
sub hasargs    { return _get( 'hasargs',    @_ ) }
sub hinthash   { return _get( 'hinthash',   @_ ) }
sub is_require { return _get( 'is_require', @_ ) }
sub line       { return _get( 'line',       @_ ) }
sub package    { return _get( 'package',    @_ ) }
sub subroutine { return _get( 'subroutine', @_ ) }
sub wantarray  { return _get( 'wantarray',  @_ ) }

#perldoc says that these aren't meant to be used externally.
#sub bitmask    { return _get(@_) }
#sub hints      { return _get(@_) }

1;
