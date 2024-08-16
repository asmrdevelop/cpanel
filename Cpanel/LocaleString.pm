package Cpanel::LocaleString;

# cpanel - Cpanel/LocaleString.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=encoding utf-8

=head1 NAME

Cpanel::LocaleString

=head1 SYNOPSIS

    #This won’t translate right away.
    my $str = Cpanel::LocaleString->new('My name is “[_1].”, 'Jonas');  ## no extract maketext

    #Only now does it translate.
    print $str->to_string();

    #This class defines a TO_JSON() method, so JSON “just works”!
    Cpanel::JSON::Dump( [$str] );

    #This is how to substitute in different args.
    my $str2 = $str->clone_with_args('Michael');

    #----------------------------------------------------------------------
    # ...or, if you need it to “just work” by serializing:

    {
        #This object maintains a different behavior for TO_JSON().
        #Once $obj goes away, TO_JSON() gets put back to default behavior.
        my $obj = Cpanel::LocaleString->set_json_to_freeze();

        my $json = Cpanel::JSON::Dump( [$str] );

        my $reconstituted = Cpanel::JSON::Load($json);

        #if you want to make sure this is right:
        Cpanel::LocaleString->is_frozen($reconstituted->[1]);

        $reconstituted->[1] = Cpanel::LocaleString->thaw(
            $reconstituted->[1],
        );
    }

=head1 DESCRIPTION

Sometimes it is handy to pass around an untranslated string with arguments.
For example, you might want to store untranslated strings in an on-disk cache
and then translate them at a later point. This module facilitates that.

It’s an “iteration” of sorts on the C<translatable()> method of storing strings
for later translation; this framework can do everything C<translatable()> can
do, and more. There is B<probably> no use case, thus, for C<translatable()> in
new code.

Using a class for strings to be translated also allows us to identify such
strings explicitly. For example:

    use Try::Tiny;

    try { $whatsit->isa('Cpanel::LocaleString') }

… tells you that C<$whatsit> is an instance of this class. There is no
corresponding way of telling that the result of a C<translatable()> call
is a string meant for translation.

=head1 DO THIS; DON’T DO THAT

    #GOOD
    Cpanel::LocaleString->new('Cancel');

    #BAD
    my $str = 'Cancel';
    Cpanel::LocaleString->new($str);

As with the regular C<maketext()> method, B<PASS A STRING LITERAL> for the
string to translate. The phrase harvester expects to see a literal as the
first argument; any other use will prevent the harvester from seeing your
phrase, so it won’t receive a translation.

=head1 ABOUT “FREEZING”

The internal serialization is not safe for general use but is useful for
saving strings to localize in a JSON structure. The format is not defined
and is meant to remain as a “black box”, so do not build anything that
parses it or builds it, please!

=cut

use strict;
use warnings;

# Prevent AutoLoad of DESTROY during my_curse
# This can likely be removed after BC-2583 is resolved
sub DESTROY { }

=head1 CLASS METHODS

=head2 I<CLASS>->new( PHRASE, ARG1, ARG2, … )

The same pattern as in the C<maketext()> function. This creates an
instance of I<CLASS>.

B<IMPORTANT!!!> As with C<maketext()>, I<PHRASE> B<must> be a string literal,
B<NOT> a variable. The reason is the same as with C<maketext()>: the phrase
parser looks for this pattern in the code and won’t know what to do with a
variable. You can probably do what you want with the C<clone_with_args()>
instance method.

=cut

sub new {

    #sanity
    if ( !length $_[1] ) {
        die 'Must include at least a string!';
    }

    return bless \@_, shift;
}

=head2 my $hold = I<CLASS>->set_json_to_freeze()

This sets I<CLASS>’s internal C<TO_JSON()> logic to serialize
rather than simply to translate to a string. This is useful, e.g.,
if you need to send I<CLASS> instances between processes or to cache them.

C<set_json_to_freeze()> returns an instance of L<Cpanel::Finally> (C<$hold>
in the example invocation above) that,
when C<DESTROY()>ed, will reset I<CLASS>’s C<TO_JSON()> back to
stringification. Please, no “funny business” with C<$hold>; let it just be
a regular lexical variable for a single execution scope.

The serialization format itself is undefined; treat it as a “black box”.
(As a debugging aid, the format does include I<CLASS> as a string in the
structure.)

B<IMPORTANT>: This is B<only> safe when the receiving end knows
what it’s looking for. Do B<NOT> use this in a context where the
recipient has to parse the structure to figure out what it is.

=cut

sub set_json_to_freeze {
    no warnings 'redefine';
    *TO_JSON = \&_to_list_ref;
    return ( __PACKAGE__ . '::_JSON_MODE' )->new();
}

=head2 I<CLASS>->thaw( REF )

Recreates the instance of I<CLASS> according to the contents of I<REF>.
I<REF> is, by definition, “frozen” as per this class’s serialization
logic.

=cut

sub thaw {

    #sanity
    if ( ref( $_[1] ) ne 'ARRAY' ) {
        die "Call thaw() on an ARRAY reference, not “$_[1]”!";
    }

    return $_[0]->new( @{ $_[1] }[ 1 .. $#{ $_[1] } ] );
}

=head2 I<CLASS>->is_frozen( REF )

B<Not for production use.>

Returns 1 or 0 to indicate whether I<REF> is (1) or is not (0)
a data structure that matches I<CLASS>’s serialization logic.
This is not useful in production since it constitutes doing
“forensics”, and the serialization logic is by definition only
safe when you know for sure what you’re dealing with.

=cut

sub is_frozen {
    {
        last if ref( $_[1] ) ne 'ARRAY';
        last if !$_[1][0]->isa( $_[0] );
        last if @{ $_[1] } < 2;

        return 1;
    }

    return 0;
}

#----------------------------------------------------------------------
# Instance methods
#-----------------------------------------------------------------------

=head1 INSTANCE METHODS

=head2 $obj->to_string()

The “workhorse” method: returns a string translation according to the current
locale.

=cut

sub to_string {
    return _locale()->makevar( @{ $_[0] } );
}

=head2 $obj->to_en_string()

Like C<to_string()>, but it always returns a string translated to the C<en>
locale (i.e., U.S. English).

=cut

sub to_en_string {
    return _locale()->makethis_base( @{ $_[0] } );
}

=head2 $obj->clone_with_args( ARG1, ARG2, … )

Returns a new instance of C<ref($self)> that reuses C<$self>’s I<PHRASE>
but uses the newly-given I<ARG1>, I<ARG2>, …

=cut

sub clone_with_args {
    return ( ref $_[0] )->new(
        $_[0][0],          #the phrase, currently stored in the object
        @_[ 1 .. $#_ ],    #the new args, supplied by the caller
    );
}

=head2 $obj->to_list()

B<You probably don’t want this.> See C<clone_with_args()>.

Returns the contents of the object as a list suitable for insertion
into C<$locale->makevar()>. B<Please use sparingly.> This is probably
only really needed for cases such as the internals of C<Cpanel::Exception>,
which explicitly desires to use its own L<Cpanel::Locale> instance rather
than this class’s.

In particular, please don’t do this:

    Cpanel::LocaleString->new( $obj->to_list() )

… because the phrase parser doesn’t know what to do with that.

=cut

sub to_list {

    # Because this module is used in very memory-sensitive contexts,
    # we should only load Cpanel::Context when it’s needed. The ugliness
    # of effectively two wantarray() checks (one explicit, the other
    # inside must_be_list()) is justified in light of the fact that
    # production use will likely avoid the need for this module.
    if ( !wantarray ) {
        require Cpanel::Context;
        Cpanel::Context::must_be_list();
    }

    return @{ $_[0] };
}

*TO_JSON = \&to_string;

#----------------------------------------------------------------------
# Guts
#----------------------------------------------------------------------

my $_locale;

sub _locale {
    return $_locale if $_locale;
    local $@;

    eval 'require Cpanel::Locale;' or do {    ## no critic qw(BuiltinFunctions::ProhibitStringyEval)
        warn "Failed to load Cpanel::Locale; falling back to substitute. Error was: $@";
    };

    eval { $_locale = Cpanel::Locale->get_handle() };
    return $_locale || bless {}, 'Cpanel::LocaleString::_Cpanel_Locale_unavailable';
}

sub _put_back {
    no warnings 'redefine';
    *TO_JSON = \&to_string;

    return;
}

#This is the internal serialization format, AS OF NOW:
#   [ package name, $phrase, @vars ]
sub _to_list_ref {
    return [ ref( $_[0] ), @{ $_[0] } ];
}

#----------------------------------------------------------------------

package Cpanel::LocaleString::_JSON_MODE;

use parent -norequire, qw(Cpanel::Finally);

sub new {
    require Cpanel::Finally;    # PPI USE OK - loaded only when needed
    return $_[0]->SUPER::new( \&Cpanel::LocaleString::_put_back );
}

package Cpanel::LocaleString::_Cpanel_Locale_unavailable;

# full namespace needed for  t/00_devel_glob_assigns.t
BEGIN {
    *Cpanel::LocaleString::_Cpanel_Locale_unavailable::makethis_base = *Cpanel::LocaleString::_Cpanel_Locale_unavailable::makevar;
}

sub makevar {
    my ( $self, $str, @maketext_opts ) = @_;

    local ( $@, $! );
    require Cpanel::Locale::Utils::Fallback;

    return Cpanel::Locale::Utils::Fallback::interpolate_variables( $str, @maketext_opts );
}

1;
