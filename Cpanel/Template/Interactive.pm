package Cpanel::Template::Interactive;

# cpanel - Cpanel/Template/Interactive.pm          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Encoder::Tiny ();
use Cpanel::Template      ();

our $output_fh;

# Note that this will still return the output in addition to displaying it as it is rendered
# Dont pass in the 'print' setting on the input_hr or print the returned data unless
# You want it to appear twice for some odd reason
sub process_template {
    my $service    = shift;
    my $input_hr   = shift;
    my $options_hr = shift || {};    # Optional

    if ( !$INC{'Template/Config.pm'} ) {

        # We have to make sure these are loaded before we redefine the OUTPUT variable
        eval '
            require Template;
            require Template::Plugin;
            require Template::Iterator;
            require Template::Context;
            require Template::Plugins;
            require Template::Filters;
            require Template::Directive;
        ';

####
#### The below avoids importing File:: which was 15% of cPanel's startup time
####
        *Template::Document::write_perl_file = \&Cpanel::Template::write_perl_file;
    }
    if ( !$INC{'Template/Parser.pm'} ) {

        # CPANEL-8497 and CPANEL-8653: Template::Parser MUST be loaded before $Template::Directive::OUTPUT is set
        require Template::Parser;
    }
    local $input_hr->{'print'}                       = 1;
    local $output_fh                                 = $input_hr->{'output_handle'} || *STDOUT;
    local $Template::Directive::OUTPUT               = 'print {$Cpanel::Template::Interactive::output_fh} ';
    local $input_hr->{'skip_template_cache'}         = 1 if !defined $input_hr->{'skip_template_cache'};
    local $input_hr->{'print_from_handle'}           = \&_print_from_handle;
    local $input_hr->{'safe_html_print_from_handle'} = \&_safe_html_print_from_handle;

    return Cpanel::Template::process_template( $service, $input_hr, $options_hr );
}

sub process_template_cached {
    my ( $service, $input_hr, $options_hr ) = @_;
    local $input_hr->{'skip_template_cache'} = 0;
    return process_template( $service, $input_hr, $options_hr );
}

sub _print_from_handle {
    my $fh = shift();

    print while readline $fh;

    return;
}

sub _safe_html_print_from_handle {
    my $fh = shift();

    while ( my $line = readline $fh ) {
        print Cpanel::Encoder::Tiny::safe_html_encode_str($line);
    }

    return;
}

1;

__END__

=head1 NAME

Cpanel/Template/Interactive.pm - Display TT interfaces as they are rendered

=head1 DESCRIPTION

  The way Template::Toolkit is designed, if you have a long running
  command that you'd like to template the output for, you have to either:

  a) Wait for the command to run so that the output can be inserted
     into the template (running the command inside the template doesn't
     change this since TT internally spools all the output until it is
     complete)

  b) Break up the template into separate pre-command and post-command
     templates that will be rendered separately.

  This module gives you a third option of having your code run in the
  middle of the template processing logic by having all TT output sent
  to STDOUT as it is rendered in memory.

=head1 EXAMPLES

  In your code:

  my $update_cr = sub { system('/usr/local/cpanel/scripts/upcp'); return $?; };
  $data->{'run_update'} = $update_cr;
  Cpanel::Template::Interactive::process_template(....);


  Then the template looks like this:

  <p>Starting update</p>
  <pre>
  [% SET status = data.run_update -%]
  </pre>
  <p>
  [% IF ! status -%]
  <p>Update completed successfully!<p>
  [% ELSE -%]
  <p>Update failed!</p>
  [% END -%]

=head1 WARNINGS

  The Template Toolkit YAPP parser would need to be substantially
  rewritten for this module to seamlessly work with all available TT
  syntax.  Doing so would be overkill for our purposes (although it
  would make a nice patch to send upstream.)  Since this module will
  send output as soon as it is rendered in memory, you'll need to
  avoid certain Template Toolkit syntax in the templates you send
  through this module.

  These directives spool output internally for processing before
  it is inserted into the final output...  Don't expect them to
  behave in a sensible fashion:

  WRAPPER
  FILTER


  Internal capturing of TT rendered data will not work correctly:
  [% rendered_template = PROCESS 'sometemplate.tmpl' -%]

  MACRO probably doesn't function correctly.

  CLEAR is pointless since the internal spool of TT rendered information
  is always empty.
