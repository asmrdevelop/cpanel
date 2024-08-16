package Cpanel::ChildErrorStringifier;

# cpanel - Cpanel/ChildErrorStringifier.pm         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Cpanel::LocaleString ();
use Cpanel::Exception    ();

#Subclasses that use this class need the attribute "_CHILD_ERROR" by default.
#If a different means of getting that number from $self is desired, just
#override CHILD_ERROR().

sub new {
    my ( $class, $CHILD_ERROR, $PROGRAM_NAME ) = @_;

    return bless { _CHILD_ERROR => $CHILD_ERROR, _PROGRAM_NAME => $PROGRAM_NAME }, $class;
}

#This function's name is in "ALLCAPS" in order to match the equivalent of $?
#in English.pm.
sub CHILD_ERROR {
    my ($self) = @_;

    return $self->{'_CHILD_ERROR'};
}

sub error_code {
    my ($self) = @_;

    return undef if !$self->CHILD_ERROR();

    return $self->CHILD_ERROR() >> 8;
}

# Convert error number into a alpha name.
# Errno doesn't do this easily.

sub error_name {
    my ($self) = @_;

    # This is an unorthodox thing to do. Technically the ONLY time %! has a non-zero value is when $! is set to the active error.
    # Because of the nature of the code, we're using the internals of Errno to get the result, regardless of the current value of $!.
    my $error_number = $self->error_code();

    return '' if ( !defined $error_number );    # Can't index a hash with undef

    require Cpanel::Errno;
    return Cpanel::Errno::get_name_for_errno_number($error_number) || q<>;
}

sub dumped_core {
    my ($self) = @_;

    return $self->CHILD_ERROR() && ( $self->CHILD_ERROR() & 128 ) ? 1 : 0;
}

sub signal_code {
    my ($self) = @_;

    return if !$self->CHILD_ERROR();

    return $self->CHILD_ERROR() & 127;
}

# XXX: Note that this returns “ZERO” if there’s no signal;
# thus, this function’s return is always truthy.
sub signal_name {
    my ($self) = @_;
    require Cpanel::Config::Constants::Perl;
    return $Cpanel::Config::Constants::Perl::SIGNAL_NAME{ $self->signal_code() };
}

sub exec_failed {
    return $_[0]->{'_exec_failed'} ? 1 : 0;
}

# This function generally gets overwritten
sub program {
    my ($self) = @_;

    return $self->{'_PROGRAM_NAME'} || undef;
}

# This function generally gets overwritten
sub set_program {
    my ( $self, $program ) = @_;

    return ( $self->{'_PROGRAM_NAME'} = $program );
}

#This returns an "autopsy" string that explains the value of CHILD_ERROR
#in human terms. It's still "UNIX-speak" because it talks about signals
#and core dumps and exit statuses (oh, my!), but it's something.
sub autopsy {
    my ($self) = @_;

    return undef if !$self->CHILD_ERROR();

    my @localized_strings = (
        $self->error_code() ? $self->_ERROR_PHRASE() : $self->_SIGNAL_PHRASE(),
        $self->_core_dump_for_phrase_if_needed(),
        $self->_additional_phrases_for_autopsy(),
    );

    return join ' ', map { $_->to_string() } @localized_strings;
}

#Useful for contexts where a full sentence would be visually “noisy”.
#This returns an untranslated string that expresses what happened as
#concisely as possible, e.g., “SIGTERM”, “exit 5”, “SIGQUIT (+core)”
sub terse_autopsy {
    my ($self) = @_;

    my $str;

    if ( $self->signal_code() ) {
        $str .= 'SIG' . $self->signal_name() . " (#" . $self->signal_code() . ")";
    }
    elsif ( my $code = $self->error_code() ) {
        $str .= "exit $code";
    }
    else {
        $str = 'OK';
    }

    if ( $self->dumped_core() ) {
        $str .= ' (+core)';
    }

    return $str;
}

sub die_if_error {
    my ($self) = @_;

    my $err = $self->to_exception();
    die $err if $err;

    return $self;
}

sub to_exception {
    my ($self) = @_;

    if ( $self->signal_code() ) {
        return Cpanel::Exception::create(
            'ProcessFailed::Signal',
            [
                process_name => $self->program(),
                signal_code  => $self->signal_code(),
                $self->_extra_error_args_for_die_if_error(),
            ],
        );
    }

    if ( $self->error_code() ) {
        return Cpanel::Exception::create(
            'ProcessFailed::Error',
            [
                process_name => $self->program(),
                error_code   => $self->error_code(),
                $self->_extra_error_args_for_die_if_error(),
            ],
        );
    }

    return undef;
}

sub _extra_error_args_for_die_if_error { }

#This method is meant to be overridden if subclasses want to add extra verbiage.
sub _additional_phrases_for_autopsy { }

sub _core_dump_for_phrase_if_needed {
    my ($self) = @_;

    if ( $self->dumped_core() ) {
        return Cpanel::LocaleString->new('The process dumped a core file.');
    }

    return;
}

#----------------------------------------------------------------------
#NOTE: Subclasses may override these. It's a bit awkward..sorry.

sub _ERROR_PHRASE {
    my ($self) = @_;

    #
    # numf loads Locales.pm so it has been removed to avoid
    # calling get_locales_obj
    #
    if ( $self->program() ) {
        return Cpanel::LocaleString->new( 'The subprocess “[_1]” reported error number [numf,_2] when it ended.', $self->program(), $self->error_code() );
    }

    return Cpanel::LocaleString->new( 'The subprocess reported error number [numf,_1] when it ended.', $self->error_code() );
}

sub _SIGNAL_PHRASE {
    my ($self) = @_;

    if ( $self->program() ) {
        return Cpanel::LocaleString->new( 'The subprocess “[_1]” ended prematurely because it received the “[_2]” ([_3]) signal.', $self->program(), $self->signal_name(), $self->signal_code() );
    }

    return Cpanel::LocaleString->new( 'The subprocess ended prematurely because it received the “[_1]” ([_2]) signal.', $self->signal_name(), $self->signal_code() );
}

#----------------------------------------------------------------------

1;
