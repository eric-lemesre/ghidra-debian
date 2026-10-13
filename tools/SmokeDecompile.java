// Test de fumée du paquet : décompile la première fonction du programme
// importé et écrit le C obtenu dans le fichier passé en argument. Vérifie
// ainsi le décompilateur natif, les spécifications SLEIGH compilées et le
// JDK (Ghidra compile ce script à l'exécution).
//@category Test
import java.io.PrintWriter;

import ghidra.app.decompiler.DecompInterface;
import ghidra.app.decompiler.DecompileResults;
import ghidra.app.script.GhidraScript;
import ghidra.program.model.listing.Function;

public class SmokeDecompile extends GhidraScript {

	@Override
	protected void run() throws Exception {
		String[] args = getScriptArgs();
		if (args.length != 1) {
			throw new IllegalArgumentException("usage : SmokeDecompile.java <fichier de sortie>");
		}
		DecompInterface decompiler = new DecompInterface();
		if (!decompiler.openProgram(currentProgram)) {
			throw new IllegalStateException(
				"décompilateur indisponible : " + decompiler.getLastMessage());
		}
		try {
			for (Function f : currentProgram.getFunctionManager().getFunctions(true)) {
				if (f.isThunk() || f.isExternal()) {
					continue;
				}
				DecompileResults r = decompiler.decompileFunction(f, 60, monitor);
				if (r.decompileCompleted()) {
					try (PrintWriter out = new PrintWriter(args[0], "UTF-8")) {
						out.print(r.getDecompiledFunction().getC());
					}
					println("décompilée : " + f.getName());
					return;
				}
			}
			throw new IllegalStateException("aucune fonction décompilée");
		}
		finally {
			decompiler.dispose();
		}
	}
}
