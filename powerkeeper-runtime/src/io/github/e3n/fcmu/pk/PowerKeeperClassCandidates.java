package io.github.e3n.fcmu.pk;

import java.util.ArrayList;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Set;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * Accepts the dynamic PowerKeeperProbe TSV output. Discovered OEM class
 * owners extend (never replace) old/new default class names.
 * No Android version or device codename is used as a compatibility gate.
 */
public final class PowerKeeperClassCandidates {
    private static final Pattern DEX_TYPE = Pattern.compile("L([A-Za-z0-9_/$]+);");
    private PowerKeeperClassCandidates() {}

    public static List<String> extract(String report) {
        Set<String> classes = new LinkedHashSet<String>();
        if (report == null) return new ArrayList<String>(classes);
        String[] lines = report.split("\n");
        for (String raw : lines) {
            String[] fields = raw.split("\t", 3);
            if (fields.length < 3 || !fields[0].startsWith("pk.")) continue;
            if (!fields[1].equals("present") && !fields[1].equals("variant")) continue;
            Matcher found = DEX_TYPE.matcher(fields[2]);
            while (found.find()) {
                String name = found.group(1).replace('/', '.');
                if (name.endsWith(".GmsObserver") || name.endsWith(".NetdExecutor") ||
                        name.endsWith(".GlobalFeatureConfigureHelper"))
                    classes.add(name);
            }
        }
        return new ArrayList<String>(classes);
    }
}
