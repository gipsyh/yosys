/*
 *  yosys -- Yosys Open SYnthesis Suite
 *
 *  Copyright (C) 2026  Yuheng Su <gipsyh.icu@gmail.com>
 *
 *  Permission to use, copy, modify, and/or distribute this software for any
 *  purpose with or without fee is hereby granted, provided that the above
 *  copyright notice and this permission notice appear in all copies.
 *
 *  THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
 *  WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
 *  MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
 *  ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
 *  WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
 *  ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
 *  OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
 *
 */

#include "kernel/ff.h"
#include "kernel/log_help.h"
#include "kernel/sigtools.h"
#include "kernel/yosys.h"

USING_YOSYS_NAMESPACE
PRIVATE_NAMESPACE_BEGIN

struct Rst2initPass : public Pass {
	Rst2initPass() : Pass("rst2init", "consume a reset signal as FF init values") {}
	bool formatted_help() override
	{
		auto *help = PrettyHelp::get_current();
		help->set_group("formal");
		return false;
	}
	void help() override
	{
		//   |---v---|---v---|---v---|---v---|---v---|---v---|---v---|---v---|---v---|---v---|
		log("\n");
		log("    rst2init [-active-low] <reset-signal>\n");
		log("\n");
		log("This pass treats the given reset signal as having been asserted before the\n");
		log("initial formal state and deasserted afterwards. Matching $sdff/$sdffe/\n");
		log("$sdffce and $adff/$adffe cells get init attributes on their Q outputs from\n");
		log("their reset values and are converted to reset-less FFs.\n");
		log("\n");
		log("    -active-low\n");
		log("        The reset is asserted when <reset-signal> is 0. By default, the\n");
		log("        reset is asserted when <reset-signal> is 1.\n");
		log("\n");
		log("This pass requires the current design to contain exactly one top module. The\n");
		log("reset signal must be one whole one-bit module input wire. The pass removes\n");
		log("the reset signal from the module ports and ties it to the inactive reset value.\n");
		log("\n");
	}

	void execute(std::vector<std::string> args, RTLIL::Design *design) override
	{
		log_header(design, "Executing RST2INIT pass (consume reset as init values).\n");

		bool requested_reset_polarity = true;
		size_t argidx;
		for (argidx = 1; argidx < args.size(); argidx++) {
			if (args[argidx] == "-active-low") {
				requested_reset_polarity = false;
				continue;
			}
			break;
		}

		if (argidx >= args.size())
			log_cmd_error("Missing reset signal argument.\n");

		string reset_signal_arg = args[argidx++];
		extra_args(args, argidx, design, false);

		int total_changed = 0;

		if (design->modules().size() != 1)
			log_error("'rst2init' requires the current design to contain exactly one module.\n");

		Module *module = design->top_module();
		if (module == nullptr)
			log_error("'rst2init' requires the current design to have a top module.\n");

		SigSpec reset_sig;
		if (!SigSpec::parse(reset_sig, module, reset_signal_arg))
			log_error("Error parsing reset signal expression '%s' in module %s.\n", reset_signal_arg, module);
		if (GetSize(reset_sig) != 1)
			log_error("Reset signal expression '%s' in module %s is %d bits wide, expected 1 bit.\n", reset_signal_arg, module,
				  GetSize(reset_sig));
		if (!reset_sig.is_wire())
			log_error("Reset signal expression '%s' must be a whole one-bit wire when removing the reset port.\n", reset_signal_arg);
		Wire *reset_wire = reset_sig.as_wire();
		if (!reset_wire->port_input || reset_wire->port_output)
			log_error("Reset signal expression '%s' must be a one-bit module input port.\n", reset_signal_arg);

		SigMap sigmap(module);
		FfInitVals initvals(&sigmap, module);
		SigSpec mapped_reset_sig = sigmap(reset_sig);

		vector<Cell *> matched_cells;
		State inactive_value = requested_reset_polarity ? State::S0 : State::S1;
		for (auto cell : vector<Cell *>(module->cells())) {
			if (!cell->type.in(ID($sdff), ID($sdffe), ID($sdffce), ID($adff), ID($adffe)))
				continue;

			FfData ff(&initvals, cell);
			bool matched = false;

			if (ff.has_srst && sigmap(ff.sig_srst) == mapped_reset_sig)
				matched = true;
			if (ff.has_arst && sigmap(ff.sig_arst) == mapped_reset_sig)
				matched = true;

			if (matched) {
				log_assert(ff.has_srst || ff.has_arst);
				bool cell_reset_polarity = ff.has_srst ? ff.pol_srst : ff.pol_arst;
				if (cell_reset_polarity != requested_reset_polarity)
					log_error("Reset signal %s is used as %s on %s.%s, but 'rst2init' was given %s polarity.\n",
						  log_signal(reset_sig), cell_reset_polarity ? "high" : "low", module, cell,
						  requested_reset_polarity ? "high" : "low");
				matched_cells.push_back(cell);
			}
		}

		for (auto cell : matched_cells) {
			FfData ff(&initvals, cell);
			Const reset_value = ff.has_srst ? ff.val_srst : ff.val_arst;
			const char *reset_kind = ff.has_srst ? "SRST" : "ARST";

			if (!reset_value.is_fully_def())
				log_error("Reset value for %s.%s contains undef bits: %s.\n", module, cell, log_signal(reset_value));

			log("Setting init on %s.%s Q=%s from %s value %s and removing reset.\n", module, cell, log_signal(ff.sig_q), reset_kind,
			    log_signal(reset_value));

			initvals.set_init(ff.sig_q, reset_value);

			if (ff.has_srst)
				ff.has_srst = false;
			if (ff.has_arst)
				ff.has_arst = false;

			ff.val_init = reset_value;
			ff.emit();

			total_changed++;
		}

		if (matched_cells.size() != 0) {
			log_assert(inactive_value == State::S0 || inactive_value == State::S1);
			IdString reset_wire_name = reset_wire->name;

			log("Removing reset signal %s.%s from module ports and tying it to inactive value %s.\n", module, reset_wire->name,
			    log_signal(inactive_value));
			reset_wire->port_input = false;
			module->fixup_ports();

			module->connect(reset_sig, inactive_value);
			Pass::call_on_module(design, module, "opt_clean -purge");

			reset_wire = module->wire(reset_wire_name);
			if (reset_wire != nullptr)
				log_error("Failed to remove reset signal %s.%s from module.\n", module, reset_wire_name);
		}

		log("Converted %d FF cells.\n", total_changed);
	}
} Rst2initPass;

PRIVATE_NAMESPACE_END
