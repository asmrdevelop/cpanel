package Cpanel::Config::ConfigObj::Interface::Meta;

# cpanel - Cpanel/Config/ConfigObj/Interface/Meta.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

our $VERSION = '1.0';

use Cpanel::Debug ();

####### FUNCTIONS #######

####### METHODS #######
sub new {
    my ( $class, $class_defaults, $consumer_obj ) = @_;

    $class = ref($class) || $class;

    if ( ref $class_defaults ne 'HASH' ) {
        $class_defaults = {};
    }

    my $default_settings = {
        'consumer'       => undef,
        'content'        => {},
        'showcase'       => {},
        'handled_locale' => 0,
    };
    %{$default_settings} = ( %{$default_settings}, %{$class_defaults} );
    my $obj = bless $default_settings, $class;

    if ($consumer_obj) {
        $obj->set_consumer($consumer_obj);
    }

    return $obj;
}

sub set_locale_handle {
    my ( $self, $locale_handle ) = @_;
    $self->{'locale_handle'} = $locale_handle;
    return 1;
}

sub set_meta_content_from_driver {
    my ( $self, $driver ) = @_;

    if ( !$driver->{'meta'} || ref $driver->{'meta'} ne 'HASH' || !scalar keys %{ $driver->{'meta'} } ) {
        $driver->{'meta'} = $self->load_driver_meta_content($driver);
    }

    # set content to that of the current driver for the meta obj
    $self->{'auto_enable'} = $driver->{'meta'}->{'auto_enable'}  || 0;
    $self->{'content'}     = $driver->{'meta'}->{'content'}      || {};
    $self->{'version'}     = $driver->{'meta'}->{'meta_version'} || 1;
    $self->{'showcase'}    = $driver->{'meta'}->{'showcase'}     || {};

    return 1;
}

# meta should be a hash w/ elements 'content' and 'meta_version', the latter
#  being a meta spec version that can be used as necessary in this classes' subs
sub load_driver_meta_content {
    my ( $self, $driver ) = @_;
    my $meta = { 'meta_version' => 1, 'content' => {} };

    # atm, modules that implement a Driver (via a Config spec) are the only
    #  valid consumers
    if ( $driver->isa('Cpanel::Config::ConfigObj::Interface::Driver') ) {

        my $module_name = $driver->module_name();

        # this is so Cpanel::Locale can be used to return a localized value in the 'content' key of the meta info hash (apparently so it won't have to load Cpanel::Locale)
        my $base_dir  = "/usr/local/cpanel";
        my $perl_file = "Cpanel/Config/ConfigObj/Driver/$module_name/META.pm";
        if ( -e "$base_dir/$perl_file" ) {
            my $meta_module = "Cpanel::Config::ConfigObj::Driver::${module_name}::META";
            if ( !$INC{$perl_file} ) {
                local $@;
                eval qq{require "$base_dir/$perl_file"; 1;};    ## no critic qw(BuiltinFunctions::ProhibitStringyEval)
                Cpanel::Debug::log_warn("Error while loading “$base_dir/$perl_file”: $@") if $@;
            }
            my $content_function = "${meta_module}::content";
            my $subref_content   = \&$content_function;

            $meta = {

                # method invocation saves a few ops/vars and is fine cause there's not input
                'meta_version' => $meta_module->meta_version(),

                # conversely, this should invoke as func so there's no need for a funky signature
                'content' => &$subref_content( $self->{'locale_handle'} ),

                # showcase is optional
                'showcase' => undef,
            };
            {
                local $@;
                eval {
                    if ( my $func = $meta_module->can('showcase') ) {
                        $meta->{'showcase'} = $func->();
                    }
                };
                Cpanel::Debug::log_warn("Error while checking showcase in “$base_dir/$perl_file”: $@") if $@;
            }
            return $meta;
        }
    }

    return $meta;
}

# the $obj is like a Driver obj
sub set_consumer {
    my ( $self, $obj ) = @_;
    my $obj_ref = ref $obj;

    die "Invalid object argument" if !( ref $obj ) || !$obj->isa('Cpanel::Config::ConfigObj');
    $self->{'consumer'} = $obj;
    return 1;
}

sub content {
    my ($self) = @_;
    return $self->{'content'};
}

sub vendor {
    my ($self) = @_;
    return $self->{'content'}->{'vendor'};
}

sub url {
    my ($self) = @_;
    return $self->{'content'}->{'url'};
}

sub name {
    my ( $self, $type ) = @_;
    if ( !$type || !exists $self->{'content'}->{'name'}->{$type} ) {
        $type = 'short';
    }
    return $self->{'content'}->{'name'}->{$type};
}

sub since {
    my ($self) = @_;
    return $self->{'content'}->{'since'};
}

sub version {
    my ($self) = @_;
    return $self->{'content'}->{'version'};
}

# The “locale_abstract_strings” format is basically JavaScript,
# but we don’t really want to load a JavaScript parser in Perl.
#
# We could parse as YAML, but that would require spaces after each comma, which
# is annoying and wasn’t a requirement of the original specification.
#
# We could parse as JSON, but that would require strings to use double quotes
# rather than single quotes--which, again, wasn’t a requirement originally.
#
# PPI would be a robust, safe choice, but its size is a liability,
# even for a lazy-load.
#
# Another option would be to write a parser based on the relevant regexps
# in Cpanel::Regex. That seems like it might be a bit brittle, though.
#
# eval() is ordinarily dangerous, but since we control the maketext
# strings, and only root can supply them anyway, it shouldn’t be a problem.
#
sub _parse_locale_abstract_strings_scalars {
    my ($code) = @_;

    local $@;
    return [ eval $code ];    ##no critic qw(ProhibitStringyEval)
}

sub abstract {
    my ($self) = @_;

    # deal with locale strings for v2+, if we have to...
    if (   defined $self->{'version'}
        && $self->{'version'} >= 2
        && !$self->{'handled_locale'}
        && scalar @{ $self->{'content'}->{'locale_abstract_strings'} }
        && defined $self->{'locale_handle'} ) {

        my @translated;

      LOCALE_PARSE:
        foreach my $string ( @{ $self->{'content'}->{'locale_abstract_strings'} } ) {
            my $strcpy = $string;

            $strcpy =~ s~^locale\.maketext\((.*)\)$~$1~ or do {    ## no extract maketext
                Cpanel::Debug::log_warn("Maketext string “$string” doesn’t match expected pattern!");
            };

            # The string at this point looks like this:
            #
            #   'My name is “[_1]”.', 'Jonas'
            #
            # We can’t parse the above as YAML because there isn’t
            # necessarily a space after the comma.
            # It appears to be safe to wrap the above in square brackets
            # ([]) and parse it as YAML, thus:
            #
            my $parsed_ar = eval { _parse_locale_abstract_strings_scalars($strcpy) } or do {
                Cpanel::Debug::log_warn("Failed to parse maketext string and arguments ($string): $@");    ## no extract maketext
                @translated = ();

                # Let it fall back to the existing abstract rather than
                # possibly localizing part of a set of instructions or
                # information, which may not make sense.
                last LOCALE_PARSE;
            };

            push @translated, $self->{'locale_handle'}->makevar(@$parsed_ar);
        }
        if (@translated) {
            $self->{'content'}->{'abstract'} = join( q< >, @translated );
            $self->{'handled_locale'} = 1;
        }
    }
    return $self->{'content'}->{'abstract'};
}

sub auto_enable {
    my ($self) = @_;
    return $self->{'auto_enable'} ? 1 : 0;
}

sub forced {
    my ($self) = @_;
    return 0 if !exists $self->{'content'}->{'forced'};
    return $self->{'content'}->{'forced'} ? 1 : 0;
}

sub readonly {
    my ($self) = @_;
    return 0 if !exists $self->{'content'}->{'readonly'};
    return $self->{'content'}->{'readonly'} ? 1 : 0;
}

#### Showcase methods ####
sub showcase {
    my ($self) = @_;
    return $self->{'showcase'};
}

sub is_recommended {
    my ($self) = @_;
    return ( $self->{'showcase'}->{'is_recommended'} ) ? 1 : 0;
}

sub is_spotlight_feature {
    my ($self) = @_;
    return ( $self->{'showcase'}->{'is_spotlight_feature'} ) ? 1 : 0;
}

1;
