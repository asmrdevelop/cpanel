package Cpanel::Output::Template;

# cpanel - Cpanel/Output/Template.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use base 'Cpanel::Output';

use Cpanel::Template ();
use Cpanel::Locale::Lazy 'lh';

my %ids;

=head1 NAME

Cpanel::Output::Template

=head1 DESCRIPTION

Provides streaming output formatting to a file handle base on a series of named templates.

=head1 CONSTRUCTOR

=head2 new(OPTS)

Creates a Cpanel::Output::Template object used to display or trap output

=head3 ARGUMENTS

HASHREF with the following possible properties:

=over

=item filehandle - GLOB - Optional

A file handle to write the data to (STDOUT is the default)

=item template_directory - STRING - Required

The full path to the source template directory. All templates and any of their custom dependencies must be located in this folder.

=item template_extension - STRING - Optional

The extention to use for the template. If not provided the extension will be .tt.html.

=item application - STRING - Required

Set the context under which the template processor runs. One of 'whostmgr', 'cpanel', 'webmail'.

=item break - STRING - Optional

String used to seperate lines. Defaults to <br/>. If you use this for non-html context, provide an appropriate alternative such as \n for plain text.

=back

=cut

my @init_params = (
    'template_directory',    # source directory for the template toolkit templates
    'template_extension',    # optional extenion to use instead of .tt.html
    'application',           # one of whostmgr, cpanel, webmail
    'break',                 # line break character sequence
    'expand_linefeeds',      # will expand internal linefeeds in strings
);

sub _init {
    my ( $self, $OPTS ) = @_;
    $OPTS = {} if !$OPTS;
    foreach my $param (@init_params) {
        $self->{$param} = delete $OPTS->{$param};
    }

    # Validate the inputs.
    die "Developer Error: The template_directory must be defined."                                if !$self->{template_directory};
    die "Developer Error: The application must be defined. Use one of whostmgr, cpanel, webmail." if !$self->{application};

    # Initialize the defaults
    $self->{template_extension} = ".tt.html" if !exists $self->{template_extension};
    $self->{break}              = "<br/>"    if !exists $self->{break};
    $self->{expand_linefeeds}   = 0          if !exists $self->{expand_linefeeds};
    return;
}

=head1 METHODS

=head2 message(TYPE, MESSAGE, ID, IGNORE, DATA)

Standard method on Cpanel::Output. This overrides the base class one to output formatted
template generated output.

=head3 ARGUMENTS

=over

=item TYPE - STRING

Type of message to output. Usually one of error, success, info, warning, notice. The type is used to
decide which template to load. If a template for the type can not be found, them an error is sent to
the stream output.

=item MESSAGE - STRING

Message to output to the stream.

=item ID - STRING - Optional

If provided, will be passed to the templates to be used as the id for the element.

=item IGNORE - UNDEF

Not used by this output module, but required to match the existing interface.

=item DATA - HASHREF

Additional data to pass to the template.

=back

=head3 RETURNS

BOOLEAN - true if the message was handled by the output formatter, false otherwise.

=cut

sub message {    ##no critic qw(Subroutines::ProhibitManyArgs) -- the message() method definiton is defined by Cpanel::Output, there was no choice in adding another parameter to pass additional data based on the existing definition of this interface.
    my ( $self, $message_type, $message, $id, $IGNORE, $DATA ) = @_;

    if ( !$id ) {
        if ( !exists $ids{$message_type} ) {
            $ids{$message_type} = 0;
        }
        $ids{$message_type}++;
        $id = "$message_type-$ids{$message_type}";
    }

    my ( $ok, $printed );
    my $template_name = $message_type . $self->{template_extension};
    my $template_path = $self->{template_directory} . "/$template_name";
    ( $ok, $printed ) = $self->_process_template(
        $template_path,
        {
            source_template      => $template_name,
            source_template_path => $template_path,
            source_directory     => $self->{template_directory},
            application          => $self->{application},
            type                 => $message_type,
            message              => $self->_expand($message),
            id                   => $id,
            ( $DATA ? (%$DATA) : () ),
        }
    );

    if ($ok) {
        print { $self->{'filehandle'} } $$printed;
        return 1;
    }
    else {
        my $error = (
            $printed
            ? lh()->maketext( "The system could not process the template ‘[_1]’ with the following error: [_2]", $template_path, $printed )
            : lh()->maketext( "The system could not process the template ‘[_1]’.", $template_path )
        ) . $self->{break};
        print { $self->{'filehandle'} } $error;
        return 0;
    }
}

# Process the template
sub _process_template {
    my ( $self, $template, $data ) = @_;
    return Cpanel::Template::process_template(
        $self->{application},
        {
            template_file => $template,
            print         => 0,
            %$data,
        }
    );
}

# Expand the newlines to the break string if enabled
sub _expand {
    my ( $self, $message ) = @_;
    return $message if !$self->{expand_linefeeds};
    $message =~ s/\012/$self->{break}/gm;
    return $message;
}

1;
