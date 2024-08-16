package Cpanel::Exception;

# cpanel - Cpanel/Exception.pm                     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=encoding utf-8

=head1 NAME

Cpanel::Exception

=head1 DISCUSSION

See L<Cpanel::Exception::CORE>’s POD for documentation of this framework.

=cut

use strict;

# set to 0 in a daemon master process to keep memory low, OK to set to 1 in a child if desired
our $LOCALIZE_STRINGS = 1;

BEGIN {
    # AUTOLOAD like: no dependencies at all here
    #   if you really want to load Cpanel::Exception in your script use Cpanel::Exception::CORE
    #   most of the time you only need to raise one exception when an error is triggered
    #   so no reasons to bloat all binaries
    my @subs = qw{
      __create
      _init
      _reset_locale
      add_auxiliary_exception
      create
      create_raw
      get
      get_auxiliary_exceptions
      get_stack_trace_suppressor
      get_string
      get_string_no_id
      id
      longmess
      new
      set
      set_id
      to_en_string
      to_en_string_no_id
      to_locale_string
      to_locale_string_no_id
      to_string
      to_string_no_id
    };

    foreach my $sub (@subs) {
        no strict 'refs';

        *$sub = sub {
            local $^W = 0;    # Cpanel::Exception::CORE is going to replace all functions

            # require() clobbers $@. (WTF?!?)
            {
                local $@;
                require Cpanel::Exception::CORE;    # PPI USE OK - this is the real Cpanel::Exception module used below
            }

            # note: no need to replace the function before calling it
            # as loading Cpanel::Exception::CORE does it for use
            return 'Cpanel::Exception'->can($sub)->(@_);
        };
    }
}

1;
