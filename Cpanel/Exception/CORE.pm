package Cpanel::Exception::CORE;

# cpanel - Cpanel/Exception/CORE.pm                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

1;

package Cpanel::Exception;

# Lightweight as possible, however use overload isn't cheap
#
use strict;

=encoding utf-8

=head1 NAME

Cpanel::Exception - cPanel’s very own exception framework

=head1 SYNOPSIS

    #Most general case: typed exception, using type-default message.
    #The array reference contains arguments for the exception itself.
    #This throws an instance of Cpanel::Exception::ExceptionClass.
    die Cpanel::Exception::create('ExceptionClass', [ key1 => val1, .. ] );

    #If you need to override the exception type’s default message...
    die Cpanel::Exception::create('ExceptionClass',
        'My message, “[_1]”.', ['Jane'],
        { key1 => val1, .. },   #exception args passed as a hashref
    );

    #Generic exception with string and string args for translation.
    #The array reference contains string arguments.
    die Cpanel::Exception->Z<>create('Translate me!', “[_1]”.', ['John']);

    #String NOT to be translated, generic exception:
    die Cpanel::Exception->Z<>create_raw('I don’t get translated.');

    #String NOT to be translated, typed exception:
    die Cpanel::Exception::Z<>create_raw('SomeType', 'I don’t get translated.');

    use Try::Tiny;  #See Try::Tiny’s POD for why to avoid eval {}.

    try {
        # ... some block that throws a Cpanel::Exception instance
    }
    catch {
        my $err = $_;

        #Static functions that can consume any exception, not just
        #a Cpanel::Exception instance.
        Cpanel::Exception::get_string($err);
        Cpanel::Exception::get_string_no_id($err);

        my $val1 = $err->get('key1');

        my $spew = "$err";  #stringification overload, includes stack trace

        warn $err->to_string();
        warn $err->to_en_string();
        warn $err->to_locale_string();
        warn $err->to_string_no_id();
        warn $err->to_en_string_no_id();
        warn $err->to_locale_string_no_id();

        $err->id();
        $err->longmess();

        #Useful only for testing, probably.
        my @auxs = $err->get_auxiliary_exceptions();

        #These mutate the exception object and are only needed in
        #particular cases. Please don’t abuse them!
        $err->add_auxiliary_exception($err2);
        $err->set_id($id_str);
    };

=head1 DISCUSSION

This exception framework is the product of several iterations of collaboration
and consultation among development teams at cPanel. It satisfies cPanel’s
particular requirements for low memory usage while at the same time providing
the useful functionality of an exception framework.

Particular features:

=over

=item * Minimal memory usage

=item * String and boolean overload: untrapped exceptions stringify
with a stack trace.

=item * Built-in (optional) localization - lazy-loaded for memory efficiency

=item * Exception IDs to facilitate correlation of error messages with logs.

=item * “Auxiliary” exceptions (see below)

=back

=head1 BEST PRACTICES

=over

=item * Use C<create_raw()> to report failures that only reflect cPanel
programming errors. There’s no point in translating failures that only
cPanel can respond to.

=item * Customer-consumable error messages (e.g., validation or filesystem
errors) should be translated.

=item * Use C<Cpanel::Exception::get_string()> for stringification unless
you’re positive that what you have is an instance of C<Cpanel::Exception>.

=item * As a general practice, avoid suppressing stack traces in log files.
Stack traces are good and useful for debugging!

=item * Custom makeZ<>text strings passed to typed exceptions should be rare.

=item * Generic exceptions probably should not receive exception attributes.
You probably should create a separate type.

=item * Identify exceptions based on type (C<isa()>) rather than exception
attributes.

=item * Preserve exception IDs when reporting an admin failure to a user.

=back

=head1 EXCEPTION IDs

This module’s IDs are designed to minimize ambiguities: for example, both
C<0> and C<O> are avoided because in some fonts they’re easy to confuse.
Likewise, because sans-serif fonts render C<I> almost identically to C<l>.
we avoid both of those characters as well. (We avoid C<1> for the same
reason.) IDs should be pronounceable and legible with maximum confidence
in comprehension.

The intent of the IDs is that error messages that the user sees may be
cross-referenced with log files. A support representative can then just
search log files on that ID string and (hopefully) find more information
on the reported failure. This is especially useful for errors that happen
behind an admin layer where we don’t want to tell the user all the gory
details of what happened but we still want a technician to be able to
investigate.

As a matter of normal course, IDs are prefixed to the exception message
as the string C<(XID …)>, where C<…> is the ID itself. Methods are provided
that allow extraction of the string without its ID for cases where this
is useful.

=head1 AUXILIARY EXCEPTIONS

Some failures require failure-prone operations as part of responding
to the initial failure. For example, if operations A, B, and C are
meant to happen as a single unit, and operation C fails, we’ll need to
undo operations B and A (in that order). If the undo of either B or A fails,
we consider that an “auxiliary” exception.

Stringification operations incorporate auxiliary exceptions.

=head1 EXCEPTION COLLECTIONS

Alternative to auxiliary exceptions, there are cases where you want to
gather several “parallel” failures up and report them all as a single
failure. For example, if you have 5 files to delete, and you definitely
want to try deleting each of them, you can collect the errors into a list
and then throw them all as a single exception:

    my @errs;
    for my $f ( @files ) {
        try { unlink_or_die($f) } catch { push @errs, $_ };
    }

    if (@errs > 1)
        die Cpanel::Exception::create('Collection', [ exceptions => \@errs ]);
    }
    elsif (@errs == 1) {
        die $errs[0];
    }

See L<Cpanel::Exception::Collection> for more information.

=head1 STACK TRACES

If an exception will always be caught and never stringified via L<overload>,
there is no gain to generating a stack trace. Since stack traces happen by
default, we generally just accept the inefficiency of this; however, in some
contexts every last bit of savings will make a difference, so we forgo
creation of the stack trace. If you need to
do this (and please, B<only> if you need to!), you can zero out all stack
traces thusly:

Good:

    {
        my $suppress = Cpanel::Exception::get_stack_trace_suppressor();

        # …
    }

Suppressed stack traces will be represented by a conspicuous,
ugly string that will grab a user’s attention if it’s seen. The point of
this is that, if you’re suppressing a stack trace, then you should never
stringify via L<overload>.

=head1 HOW TO CREATE YOUR OWN EXCEPTION CLASS

=over

=item 0. Make sure there isn’t already an exception class that does what
you need. Also make sure that you really do need a custom exception type;
it’s generally only needed if you need the exception to be machine-parsable.

=item 1. Create your exception in the C<Cpanel::Exception> namespace
(e.g., C<Cpanel::Exception::MyType>), and make it subclass
C<Cpanel::Exception>—directly or indirectly.

=item 2. You probably want to create a C<_default_phrase()> method, though
strictly speaking it’s optional. Use the C<get()> method here to retrieve
exception parameters. (You can also override C<get()>!) You’ll return either:

=over

=item a. an instance of L<Cpanel::LocaleString>, which the exception will
localize as needed. There are dozens of examples of this in the repository.

=item b. a plain string, which the exception will not localize. Use cases
for this should be rare.

=back

=item 3. You can also override the C<_spew()> method to control how your
class’s instances will stringify via L<overload>.

=back

=head1 POLYMORPHIC FUNCTIONS/METHODS

=cut

BEGIN {
    # when CORE is loaded we do not need to load the fake module
    $INC{'Cpanel/Exception.pm'} = '__BYPASSED__';
}

our $_SUPPRESS_STACK_TRACES = 0;

our $_EXCEPTION_MODULE_PREFIX = 'Cpanel::Exception';
our $IN_EXCEPTION_CREATION    = 0;

#read from tests
our $_suppressed_msg = '__STACK_TRACE_SUPPRESSED__YOU_SHOULD_NEVER_SEE_THIS_MESSAGE__';

my $PACKAGE = 'Cpanel::Exception';
my $locale;

#Avoid 0, 1, i/I, l/L, and o/O since some fonts obscure the difference.
my @ID_CHARS = qw( a b c d e f g h j k m n p q r s t u v w x y z 2 3 4 5 6 7 8 9 );

my $ID_LENGTH = 6;

#STATIC methods first. These generally are the means to use when calling
#this module.

use Cpanel::ExceptionMessage::Raw ();
use Cpanel::LoadModule::Utils     ();

use constant _TRUE => 1;

use overload (
    '""'     => \&__spew,
    bool     => \&_TRUE,
    fallback => 1,
);

BEGIN {
    die "Cannot compile Cpanel::Exception::CORE" if $INC{'B/C.pm'} && $0 !~ m{cpkeyclt|cpsrvd\.so|t/large};
}

sub _init { return 1 }    # legacy

=head2 Cpanel::Exception::create

=over

=item Cpanel::Exception::Z<>create( $class, \@key_values );

=item Cpanel::Exception::Z<>create( $class, $mt_string, \@mt_string_args, { @key_values } );

=item Cpanel::Exception->Z<>create( \@key_values );

=item Cpanel::Exception->Z<>create( $mt_string, \@mt_string_args, { @key_values } );

=back

The “workhorse” of this framework: this is how you create localized
exceptions, which are probably the majority of exceptions we want to create.

You’ll generally want to call this as a static function, e.g.,
C<Cpanel::Exception::Z<>create(…)>. This creates a specific type of exception,
named by the given C<$class>: if C<$class> is C<'My::Type'>, you’ll get an
instance of C<Cpanel::Exception::My::Type> back.

Generally, you’ll also want B<NOT> to pass in C<$mt_string> nor
C<\@mt_string_args>; these are for when you want a custom makeZ<>text string.
This really shouldn’t happen for specific exception types; are you sure you
shouldn’t create a new exception type instead?

When called as an object method (e.g., C<Cpanel::Exception-E<gt>create()>),
you’ll get back an instance of C<Cpanel::Exception>. This is a “generic”
exception type. You’ll almost certainly want to pass in a makeZ<>text string
and arguments here. You can also still pass in key/values, but you really
probably should create (or use) a separate exception type if you’re using
this.

=cut

sub create {
    my ( $exception_type, @args ) = @_;

    _init();

    if ($IN_EXCEPTION_CREATION) {
        _load_cpanel_carp();
        die 'Cpanel::Carp'->can('safe_longmess')->("Attempted to create a “$exception_type” exception with arguments “@args” while creating exception “$IN_EXCEPTION_CREATION->[0]” with arguments “@{$IN_EXCEPTION_CREATION->[1]}”.");
    }
    local $IN_EXCEPTION_CREATION = [ $exception_type, \@args ];

    if ( $exception_type !~ m/\A[A-Za-z0-9_]+(?:\:\:[A-Za-z0-9_]+)*\z/ ) {
        die "Invalid exception type: $exception_type";
    }

    my $perl_class;
    if ( $exception_type eq __PACKAGE__ ) {
        $perl_class = $exception_type;
    }
    else {
        $perl_class = "${_EXCEPTION_MODULE_PREFIX}::$exception_type";
    }

    #A few exception subclasses do not need to be loaded externally.
    _load_perl_module($perl_class) unless $perl_class->can('new');

    # For memory we store exception args as an arrayref
    # and later convert it to a hash if the exception is throw
    if ( $args[0] && ref $args[0] eq 'ARRAY' && scalar @{ $args[0] } > 1 ) {
        $args[0] = { @{ $args[0] } };
    }

    return $perl_class->new(@args);
}

=head2 create_raw

=over

=item Cpanel::Exception::create_raw( $class, $string );

=item Cpanel::Exception->create_raw( $string );

=back

C<create_raw()> creates untranslated exceptions. If your exception reports
a failure on the part of cPanel, and you just want to have a sanity check
in place, this is how you do that. It avoids the translation layer, and it
prevents our phrase parser from seeing it and harvesting the string for
translation.

=cut

sub create_raw {
    my ( $class, $msg, @extra_args ) = @_;

    _init();

    my $msg_obj = 'Cpanel::ExceptionMessage::Raw'->new($msg);

    #There seems no reason to support create_raw for exception collections.
    #For now, let's avoid it; if a good use case crops up, it's easy to delete
    #this block and update the tests.
    if ( $class =~ m<\A(?:\Q${_EXCEPTION_MODULE_PREFIX}::\E)?Collection\z> ) {
        die "Use create('Collection', ..) to create a Cpanel::Exception::Collection object.";
    }

    return create( $class, $msg_obj, @extra_args );
}

#PRIVATE METHOD. Do not call outside this module, even in subclasses.
# do not use Cpanel::LoadModule here
#   lite version for Cpanel::Exception internals to avoid circular dependencies
sub _load_perl_module {
    my ($module) = @_;

    local ( $!, $@ );

    if ( !defined $module ) {
        die __PACKAGE__->new( 'Cpanel::ExceptionMessage::Raw'->new("load_perl_module requires a module name.") );
    }

    # check if in %INC
    return 1 if Cpanel::LoadModule::Utils::module_is_loaded($module);

    # requires as module can be Foo.pm or Foo
    my $module_name = $module;
    $module_name =~ s{\.pm$}{};

    # check valid name
    if ( !Cpanel::LoadModule::Utils::is_valid_module_name($module_name) ) {
        die __PACKAGE__->new( 'Cpanel::ExceptionMessage::Raw'->new("load_perl_module requires a valid module name: '$module_name'.") );
    }

    {
        eval qq{use $module (); 1 }
          or die __PACKAGE__->new( 'Cpanel::ExceptionMessage::Raw'->new("load_perl_module cannot load '$module_name': $@") )
    }

    return 1;
}

#We don’t want people calling new() directly.
#
#Args are:
#   1) OPTIONAL. maketext() phrase OR Cpanel::ExceptionMessage object       ## no extract maketext
#       If not given, we check for a _default_phrase() method
#       and determine the phrase that way.
#   2) OPTIONAL. arrayref of args to the maketext() phrase, or              ## no extract maketext
#       _default_phrase() if the phrase is not given.
#       This argument is ignored if the first argument was a
#       Cpanel::ExceptionMessage object.
#   3) OPTIONAL. hashref of metadata to attach to the object
sub new {
    my ( $class, @args ) = @_;

    @args = grep { defined } @args;

    my $self = {};

    bless $self, $class;

    if ( ref $args[-1] eq 'HASH' ) {
        $self->{'_metadata'} = pop @args;
    }

    #Undocumented: you can pass in your own “longmess” coderef
    #and get a custom stack-trace-maker. (Is this used??)
    if ( defined $self->{'_metadata'}->{'longmess'} ) {
        $self->{'_longmess'} = &{ $self->{'_metadata'}->{'longmess'} }($self)
          if $self->{'_metadata'}->{'longmess'};
    }
    elsif ($_SUPPRESS_STACK_TRACES) {
        $self->{'_longmess'} = $_suppressed_msg;
    }
    else {
        if ( !$INC{'Carp.pm'} ) { _load_carp(); }
        $self->{'_longmess'} = scalar do {

            #NOTE: @CARP_NOT doesn't work for this for some reason.
            local $Carp::CarpInternal{'Cpanel::Exception'} = 1;
            local $Carp::CarpInternal{$class} = 1;

            'Carp'->can('longmess')->();
        };
    }

    _init();

    $self->{'_auxiliaries'} = [];

    if ( UNIVERSAL::isa( $args[0], 'Cpanel::ExceptionMessage' ) ) {
        $self->{'_message'} = shift @args;
    }
    else {
        my @mt_args;

        if ( @args && !ref $args[0] ) {
            @mt_args = ( shift @args );

            if ( ref $args[0] eq 'ARRAY' ) {
                push @mt_args, @{ $args[0] };
            }
        }
        else {

            # Store these arguments so we can reuse them to update the phrase.
            $self->{'_orig_mt_args'} = $args[0];

            my $phrase = $self->_default_phrase( $args[0] );

            if ($phrase) {

                # Case “a.” in the _default_phrase documentation below:
                # an object, which we assume to be a Cpanel::LocaleString.
                if ( ref $phrase ) {
                    @mt_args = $phrase->to_list();
                }

                # Case “b.” in the _default_phrase documentation below:
                # a plain, unlocalizable string
                else {
                    $self->{'_message'} = Cpanel::ExceptionMessage::Raw->new($phrase);
                    return $self;
                }
            }
        }

        if ( my @extras = grep { !ref } @args ) {
            die __PACKAGE__->new( 'Cpanel::ExceptionMessage::Raw'->new("Extra scalar(s) passed to $PACKAGE! (@extras)") );
        }

        #Be helpful, in case this ever happens.
        if ( !length $mt_args[0] ) {
            die __PACKAGE__->new( 'Cpanel::ExceptionMessage::Raw'->new("No args passed to $PACKAGE constructor!") );
        }

        $self->{'_mt_args'} = \@mt_args;
    }

    return $self;
}

#----------------------------------------------------------------------

=head1 STATIC FUNCTIONS

=head2 Cpanel::Exception::get_string($exception)

Returns a string version of the passed-in exception. That
passed-in exception can be anything: a string, a C<Cpanel::Exception>
instance, or an instance of some other exception framework (e.g., those
for L<autodie> or L<Template>).

For C<Cpanel::Exception> instances, this calls the C<to_string()>
method.

=cut

#XXX Please avoid $no_id_yn; call get_string_no_id() instead.
#TODO Convert get_string(.., 'no_id') calls to use the other function,
#then drop the flag.
sub get_string {
    my ( $exc, $no_id_yn ) = @_;

    return get_string_no_id($exc) if $no_id_yn;

    return _get_string( $exc, 'to_string' );
}

=head2 Cpanel::Exception::get_string_no_id($exception)

Like C<get_string()>, except that for C<Cpanel::Exception> instances,
this calls the C<to_string_no_id()> method.

=cut

sub get_string_no_id {
    my ($exc) = @_;

    return _get_string( $exc, 'to_string_no_id' );
}

sub _get_string {
    my ( $exc, $cp_exc_stringifier_name ) = @_;

    return $exc if !ref $exc;

    {
        local $@;
        my $ret = eval { $exc->$cp_exc_stringifier_name() };
        return $ret if defined $ret && !$@ && !ref $ret;
    }

    # This is a common enough pattern that it’s worth checking for;
    # currently it is used in Cpanel::Update::*. In the future
    # we may want to consider refactoring this to use Cpanel::Exception
    # in order to avoid having to accomodate two systems.
    if ( ref $exc eq 'HASH' && $exc->{'message'} ) {
        return $exc->{'message'};
    }

    if ( $INC{'Cpanel/YAML.pm'} ) {
        local $@;
        my $ret = eval { 'Cpanel::YAML'->can('Dump')->($exc); };
        return $ret if defined $ret && !$@;
    }

    if ( $INC{'Cpanel/JSON.pm'} ) {
        local $@;
        my $ret = eval { 'Cpanel::JSON'->can('Dump')->($exc); };
        return $ret if defined $ret && !$@;
    }

    return $exc;
}

#Currently we don’t expose an apply_id() function because it’s
#easy just to create a new Cpanel::Exception object with a raw-text
#message. (e.g., Cpanel::Exception->create_raw("..."))

sub _create_id {

    # Without this we’ll get the same error ID across forked processes.
    # e.g.:
    #
    #   perl -E'srand(); fork or do { say rand(); exit }; say rand()'
    #
    srand();

    return join(
        q<>,
        map { $ID_CHARS[ int rand( 0 + @ID_CHARS ) ]; } ( 1 .. $ID_LENGTH ),
    );
}

sub get_stack_trace_suppressor {
    return Cpanel::Exception::_StackTraceSuppression->new();
}

#----------------------------------------------------------------------

=head1 INSTANCE METHODS

=head2 OBJ->set_id( NEW_ID )

Sets the object’s ID. Returns the object.

=cut

#This is useful when you want to recreate an exception, e.g.,
#from the admin layer in userland.
#
#It returns the object, so you can “chain” this method.
#
sub set_id {
    my ( $self, $new_id ) = @_;
    $self->{'_id'} = $new_id;
    return $self;
}

=head2 OBJ->id()

Returns the object’s ID.

=cut

#The IDs can be any of (scalar @ID_CHARS) ** $ID_LENGTH possible values.
#
sub id {
    my ($self) = @_;

    return $self->{'_id'} ||= _create_id();
}

=head2 OBJ->set( KEY => VALUE )

Sets the object’s stored value for C<KEY>. Returns OBJ.

=cut

sub set {
    my ( $self, $key ) = @_;

    $self->{'_metadata'}{$key} = $_[2];

    # If we used the _default_phrase() earlier, then we want to
    # recompute the phrase.
    if ( exists $self->{'_orig_mt_args'} ) {
        my $phrase = $self->_default_phrase( $self->{'_orig_mt_args'} );

        if ($phrase) {
            if ( ref $phrase ) {
                $self->{'_mt_args'} = [ $phrase->to_list() ];
                undef $self->{'_message'};
            }
            else {
                $self->{'_message'} = Cpanel::ExceptionMessage::Raw->new($phrase);
            }
        }
    }

    return $self;
}

=head2 OBJ->get( KEY )

Returns the object’s stored value for C<KEY>. If C<Clone> is loadable,
then a clone of the value will be returned instead.

=cut

#For getting metadata values
sub get {
    my ( $self, $key ) = @_;

    my $v = $self->{'_metadata'}{$key};

    if ( my $reftype = ref $v ) {
        local $@;
        if ( $reftype eq 'HASH' ) {
            $v = { %{$v} };    # shallow copy
        }
        elsif ( $reftype eq 'ARRAY' ) {
            $v = [ @{$v} ];    # shallow copy
        }
        elsif ( $reftype eq 'SCALAR' ) {
            $v = \${$v};       # shallow copy
        }
        else {
            local ( $@, $! );
            require Cpanel::ScalarUtil;

            if ( $reftype ne 'GLOB' && !Cpanel::ScalarUtil::blessed($v) ) {

                # We can't reliably clone blessed objects since they may contain
                # XS or memory references which can result in leaking memory instead
                warn if !eval {
                    _load_perl_module('Clone') if !$INC{'Clone.pm'};
                    $v = 'Clone'->can('clone')->($v);
                };
            }
        }
    }

    return $v;
}

=head2 OBJ->get_all_metadata()

Returns all of the object’s stored values. If C<Clone> is loadable,
then clones of the values will be returned instead.

=cut

sub get_all_metadata {
    my $self = shift;
    my %metadata_copy;
    for my $key ( keys %{ $self->{'_metadata'} } ) {
        $metadata_copy{$key} = $self->get($key);
    }
    return \%metadata_copy;
}

my $loaded_LocaleString;

sub _require_LocaleString {
    return $loaded_LocaleString ||= do {
        local $@;
        eval 'require Cpanel::LocaleString; 1;' or die $@;    ## no critic qw(BuiltinFunctions::ProhibitStringyEval) -  # PPI NO PARSE - load on demand
        1;
    };
}

my $loaded_ExceptionMessage_Locale;

sub _require_ExceptionMessage_Locale {
    return $loaded_ExceptionMessage_Locale ||= do {
        local $@;
        eval 'require Cpanel::ExceptionMessage::Locale; 1;' or die $@;    ## no critic qw(BuiltinFunctions::ProhibitStringyEval) - # PPI NO PARSE - load on demand
        1;
    };
}

sub _default_phrase {
    _require_LocaleString();
    return 'Cpanel::LocaleString'->new( 'An unknown error in the “[_1]” package has occurred.', scalar ref $_[0] );    # PPI NO PARSE - loaded above
}

=head2 OBJ->id()

Returns the object’s stack trace as a string.

=cut

sub longmess {
    my ($self) = @_;

    return ''           if $self->{'_longmess'} eq $_suppressed_msg;
    _load_cpanel_carp() if !$INC{'Cpanel/Carp.pm'};
    return Cpanel::Carp::sanitize_longmess( $self->{'_longmess'} );
}

=head2 OBJ->to_string() OBJ->to_string_no_id()

Returns a stringification of the object in both the C<en> locale and
the running process’s specific cPanel locale. If those two are the same,
then these return the same output as
C<to_en_string()>/C<to_en_string_no_id()> and
C<to_locale_string()>/C<to_locale_string_no_id()>.

This will include any auxiliary exceptions. It will NOT include a
stack trace.

=cut

sub to_string {
    my ($self) = @_;

    return _apply_id_prefix( $self->id(), $self->to_string_no_id() );
}

sub to_string_no_id {
    my ($self) = @_;

    my $string = $self->to_locale_string_no_id();

    if ( $self->_message()->get_language_tag() ne 'en' ) {
        my $en_string = $self->to_en_string_no_id();
        $string .= "\n$en_string" if ( $en_string ne $string );
    }

    return $string;
}

sub _apply_id_prefix {
    my ( $id, $msg ) = @_;

    #Let “XID” be untranslated so that techs can always find it.
    return sprintf "(XID %s) %s", $id, $msg;
}

=head2 OBJ->to_en_string() OBJ->to_en_string_no_id()

Returns the object’s stringification in the C<en> locale.
It includes auxiliary exceptions but does not include a stack trace.

=cut

sub to_en_string {
    my ($self) = @_;

    return _apply_id_prefix( $self->id(), $self->to_en_string_no_id() );
}

sub to_en_string_no_id {
    my ($self) = @_;

    return $self->_message()->to_en_string() . $self->_stringify_auxiliaries('to_en_string');
}

=head2 OBJ->to_locale_string()  OBJ->to_locale_string_no_id()

Returns the object’s stringification in the running process’s
cPanel-specific locale. It includes auxiliary exceptions but
does not include a stack trace.

=cut

sub to_locale_string {
    my ($self) = @_;

    return _apply_id_prefix( $self->id(), $self->to_locale_string_no_id() );
}

#Useful for recreating an exception.
sub to_locale_string_no_id {
    my ($self) = @_;

    return $self->_message()->to_locale_string() . $self->_stringify_auxiliaries('to_locale_string');
}

=head2 OBJ->add_auxiliary_exception( NEW_EXC )

Adds C<NEW_EXC> to the object’s internal list of exceptions.
C<NEW_EXC> does not need to be an instance of C<Cpanel::Exception>.

=cut

#This is best used for *auxiliary* exceptions; e.g., a rollback fails within
#a set of pseudo-atomic commands.
#
#Right now, there is no implementation of "outer" and "inner" exceptions.
#
sub add_auxiliary_exception {
    my ( $self, $aux ) = @_;

    return push @{ $self->{'_auxiliaries'} }, $aux;
}

=head2 OBJ->get_auxiliary_exceptions()

Returns the object’s internal list of exceptions.

=cut

sub get_auxiliary_exceptions {
    my ($self) = @_;

    die 'List context only!' if !wantarray;    #Can’t use Cpanel::Context

    return @{ $self->{'_auxiliaries'} };
}

#This allows subclasses to override _spew().
sub __spew {
    my ($self) = @_;

    return $self->_spew();
}

sub _spew {
    my ($self) = @_;

    return ref($self) . '/' . join "\n", $self->to_string() || '<no message>', $self->longmess() || ();
}

sub _stringify_auxiliaries {
    my ( $self, $method ) = @_;

    my @lines;

    if ( @{ $self->{'_auxiliaries'} } ) {

        # Necessary to prevent clobberage of $@.
        local $@;

        _require_LocaleString();

        my $intro = 'Cpanel::LocaleString'->new( 'The following additional [numerate,_1,error,errors] occurred:', 0 + @{ $self->{'_auxiliaries'} } );    # PPI NO PARSE - required above

        #Keep these using the same _locale() as this class
        #rather than the one for Cpanel::LocaleString.
        if ( $method eq 'to_locale_string' ) {
            push @lines, _locale()->makevar( $intro->to_list() );
        }
        elsif ( $method eq 'to_en_string' ) {
            push @lines, _locale()->makethis_base( $intro->to_list() );
        }
        else {
            die "Invalid method: $method";
        }

        push @lines, map { UNIVERSAL::isa( $_, __PACKAGE__ ) ? $_->$method() : $_ } @{ $self->{'_auxiliaries'} };
    }

    return join q<>, map { "\n$_" } @lines;
}

#For JSON::XS
*TO_JSON = \&to_string;

sub _locale {
    return $locale ||= do {

        #prevent $@-clobbering problems with overload.pm.
        local $@;

        # Do not use LoadModule as we do not have exception handling here
        eval 'require Cpanel::Locale; 1;' or die $@;

        'Cpanel::Locale'->get_handle();    # hide from perlcc
    };
}

#For testing.
sub _reset_locale {
    return undef $locale;
}

# Do no use LoadModule as we do not have exception handling here
sub _load_carp {
    if ( !$INC{'Carp.pm'} ) {

        #prevent $@-clobbering problems with overload.pm.
        local $@;
        eval 'require Carp; 1;' or die $@;    ## no critic qw(BuiltinFunctions::ProhibitStringyEval) -- hide from perlcc
    }

    return;
}

# Do no use LoadModule as we do not have exception handling here
sub _load_cpanel_carp {
    if ( !$INC{'Cpanel/Carp.pm'} ) {

        #prevent $@-clobbering problems with overload.pm.
        local $@;
        eval 'require Cpanel::Carp; 1;' or die $@;    ## no critic qw(BuiltinFunctions::ProhibitStringyEval) -- hide from perlcc
    }

    return;
}

sub _message {
    my ($self) = @_;

    return $self->{'_message'} if $self->{'_message'};

    #Don’t offend code that’s vulnerable to $! clobberage.
    local $!;
    if ($Cpanel::Exception::LOCALIZE_STRINGS) {    # the default
        _require_ExceptionMessage_Locale();
        return ( $self->{'_message'} ||= 'Cpanel::ExceptionMessage::Locale'->new( @{ $self->{'_mt_args'} } ) );    # PPI NO PARSE - required above
    }

    # For exceptions in daemons that require low memory profiles
    return ( $self->{'_message'} ||= Cpanel::ExceptionMessage::Raw->new( Cpanel::ExceptionMessage::Raw::convert_localized_to_raw( @{ $self->{'_mt_args'} } ) ) );
}

#======================================================================

package Cpanel::Exception::_StackTraceSuppression;

sub new {
    my ($class) = @_;

    $Cpanel::Exception::_SUPPRESS_STACK_TRACES++;

    return bless [], $class;
}

sub DESTROY {
    $Cpanel::Exception::_SUPPRESS_STACK_TRACES--;
    return;
}

1;
