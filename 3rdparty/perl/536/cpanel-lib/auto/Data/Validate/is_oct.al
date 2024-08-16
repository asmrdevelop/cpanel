# NOTE: Derived from blib/lib/Data/Validate.pm.
# Changes made here will be lost when autosplit is run again.
# See AutoSplit.pm.
package Data::Validate;

#line 350 "blib/lib/Data/Validate.pm (autosplit into blib/lib/auto/Data/Validate/is_oct.al)"
# -------------------------------------------------------------------------------


sub is_oct {
	my $self = shift if ref($_[0]);
	my $value = shift;
	
	return unless defined $value;
	
	return if $value =~ /[^0-7]/;
		
	my $int = oct($value);
	return unless (defined $int);
	my $oct = sprintf "%o", $int;
	return $oct if ($oct eq $value);
	
	# handle zero stripping
	if (my ($z) = $value =~ /^(0+)/) {
		return "$z$oct" if ("$z$oct" eq $value);
	}
	
	return;
}

# end of Data::Validate::is_oct
1;
