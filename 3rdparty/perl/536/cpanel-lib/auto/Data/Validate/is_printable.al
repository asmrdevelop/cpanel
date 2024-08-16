# NOTE: Derived from blib/lib/Data/Validate.pm.
# Changes made here will be lost when autosplit is run again.
# See AutoSplit.pm.
package Data::Validate;

#line 820 "blib/lib/Data/Validate.pm (autosplit into blib/lib/auto/Data/Validate/is_printable.al)"
# -------------------------------------------------------------------------------


sub is_printable{
	my $self = shift if ref($_[0]);
	my $value = shift;
	
	return unless defined($value);
	return '' if $value eq ''; # allow for empty string
	
	my($untainted) = $value =~ /([[:print:][:space:]]+)/i;
	
	return unless defined($untainted);
	return unless $untainted eq $value;

	return $untainted;
	
}

# end of Data::Validate::is_printable
1;
