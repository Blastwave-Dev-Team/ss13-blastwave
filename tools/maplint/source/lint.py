import re
from typing import Optional, Union

from .common import Constant, Typepath
from .dmm import DMM, Content
from .error import MaplintError, MapParseError

def expect(condition, message):
    if not condition:
        raise MapParseError(message)

"""Create an error linked to a specific content instance"""
def fail_content(content: Content, message: str) -> MaplintError:
    return MaplintError(message, content.filename, content.starting_line)

class TypepathExtra:
    typepath: Typepath
    exact: bool = False
    wildcard: bool = False

    def __init__(self, typepath):
        if typepath == '*':
            self.wildcard = True
            return

        if typepath.startswith('='):
            self.exact = True
            typepath = typepath[1:]

        self.typepath = Typepath(typepath)

    def matches_path(self, path: Typepath):
        if self.wildcard:
            return True

        if self.exact:
            return self.typepath == path

        if len(self.typepath.segments) > len(path.segments):
            return False

        return self.typepath.segments == path.segments[:len(self.typepath.segments)]

BYOND_DIR_OFFSETS = {
    1: (0, -1),  # NORTH: toward the start of a TGM column
    2: (0, 1),   # SOUTH
    4: (1, 0),   # EAST
    8: (-1, 0),  # WEST
}
BYOND_REVERSE_DIR = {1: 2, 2: 1, 4: 8, 8: 4}
BYOND_DIR_NAMES = {1: "north", 2: "south", 4: "east", 8: "west"}
DEFAULT_ATOM_DIR = 2


def parse_atom_dir(identified: Content) -> int:
    value = identified.var_edits.get("dir", DEFAULT_ATOM_DIR)
    try:
        return int(value)
    except (TypeError, ValueError):
        return DEFAULT_ATOM_DIR


def content_piping_layer(content: Content) -> Optional[int]:
    if "piping_layer" in content.var_edits:
        try:
            return int(content.var_edits["piping_layer"])
        except (TypeError, ValueError):
            return None
    match = re.search(r"/layer(\d+)(?:/|$)", str(content.path))
    if match:
        return int(match.group(1))
    return None


def parse_neighbor_list(neighbors_data) -> list:
    expect(isinstance(neighbors_data, list) or isinstance(neighbors_data, dict), "neighbors must be a list, or a dictionary keyed by type.")
    if isinstance(neighbors_data, dict):
        return [AtomNeighbor(typepath, data) for typepath, data in neighbors_data.items()]
    return [AtomNeighbor(typepath) for typepath in neighbors_data]


class AtomNeighbor:
    identical: bool = False
    typepath: Optional[TypepathExtra] = None
    pattern: Optional[re.Pattern] = None
    ignore: list[TypepathExtra] = []
    piping_layer: Optional[int] = None

    def __init__(self, typepath, data = {}):
        if typepath.upper() != typepath:
            self.typepath = TypepathExtra(typepath)

        if data is None:
            return

        expect(isinstance(data, dict), "Banned neighbor must be a dictionary.")

        if "identical" in data:
            self.identical = data.pop("identical")
        expect(isinstance(self.identical, bool), "identical must be a boolean.")

        if "pattern" in data:
            self.pattern = re.compile(data.pop("pattern"))

        if "ignore" in data:
            ignore_data = data.pop("ignore")
            expect(isinstance(ignore_data, list), "ignore must be a list of typepaths.")
            self.ignore = [TypepathExtra(tp) for tp in ignore_data]

        if "piping_layer" in data:
            self.piping_layer = data.pop("piping_layer")
        expect(self.piping_layer is None or isinstance(self.piping_layer, (int, float)), "piping_layer must be a number.")
        if self.piping_layer is not None:
            self.piping_layer = int(self.piping_layer)

        expect(len(data) == 0, f"Unknown key in banned neighbor: {', '.join(data.keys())}.")

    def matches(self, identified: Content, neighbor: Content):
        if self.identical:
            if identified.path != neighbor.path:
                return False

            if identified.var_edits != neighbor.var_edits:
                return False

            return True

        if self.piping_layer is not None and content_piping_layer(neighbor) != self.piping_layer:
            return False

        if self.typepath is not None:
            if self.typepath.matches_path(neighbor.path):
                return True

        if self.pattern is not None:
            if self.pattern.match(str(neighbor.path)):
                return True

        return False

    def to_string(self) -> str:
        label = None
        if self.typepath is not None:
            label = self.typepath.typepath.path
        elif self.pattern is not None:
            label = self.pattern.pattern
        else:
            label = "neighbor"
        if self.piping_layer is not None:
            return f"{label} (piping layer {self.piping_layer})"
        return label

Choices = list[Constant] | re.Pattern

def extract_choices(data, key) -> Optional[Choices]:
    if key not in data:
        return None

    constants_data = data.pop(key)

    if isinstance(constants_data, list):
        constants: list[Constant] = []

        for constant_data in constants_data:
            if isinstance(constant_data, str):
                constants.append(constant_data)
            elif isinstance(constant_data, int):
                constants.append(float(constant_data))
            elif isinstance(constant_data, float):
                constants.append(constant_data)

        return constants
    elif isinstance(constants_data, dict):
        if "pattern" in constants_data:
            pattern = constants_data.pop("pattern")
            return re.compile(pattern)

        raise MapParseError(f"Unknown key in {key}: {', '.join(constants_data.keys())}.")

    raise MapParseError(f"{key} must be a list of constants, or a pattern")

class BannedVariable:
    variable: str
    allow: Optional[Choices] = None
    deny: Optional[Choices] = None

    def __init__(self, variable, data = {}):
        self.variable = variable

        if data is None:
            return

        self.allow = extract_choices(data, "allow")
        self.deny = extract_choices(data, "deny")

        expect(len(data) == 0, f"Unknown key in banned variable {variable}: {', '.join(data.keys())}.")

    def run(self, identified: Content) -> str:
        if identified.var_edits[self.variable] is None:
            return None

        if self.allow is not None:
            if isinstance(self.allow, list):
                if identified.var_edits[self.variable] not in self.allow:
                    return f"Must be one of {', '.join(map(str, self.allow))}"
            elif not self.allow.match(str(identified.var_edits[self.variable])):
                return f"Must match {self.allow.pattern}"

            return None

        if self.deny is not None:
            if isinstance(self.deny, list):
                if identified.var_edits[self.variable] in self.deny:
                    return f"Must not be one of {', '.join(map(str, self.deny))}"
            elif self.deny.match(str(identified.var_edits[self.variable])):
                return f"Must not match {self.deny.pattern}"

            return None

        return f"This variable is not allowed for this type."

# Base class for conditional rules
class ConditionalRule:
    def is_met(self, identified: Content) -> bool:
        raise NotImplementedError("This method should be implemented by subclasses.")

    def match_string(self, parent_intersection: bool) -> str:
        raise NotImplementedError("This method should be implemented by subclasses")

# A single conditional expression
class WhenCondition(ConditionalRule):
    condition: str
    match_set: Optional[re.Match[str]]
    match_not_set: Optional[re.Match[str]]
    match_equal: Optional[re.Match[str]]
    match_not_equal: Optional[re.Match[str]]
    match_like: Optional[re.Match[str]]

    def __init__(self, condition: str):
        self.condition = condition
        self.match_set = re.match("(.+) is set", condition)
        self.match_not_set = re.match("(.+) is not set", condition)
        self.match_equal = re.match("(.+) is '(.+)'", condition)
        self.match_not_equal = re.match("(.+) is not '(.+)'", condition)
        self.match_like = re.match("(.+) like '(.+)'", condition)
        matches = 0
        if self.match_set is not None:
            matches = matches + 1
        if self.match_not_set is not None:
            matches = matches + 1
        if self.match_equal is not None:
            matches = matches + 1
        if self.match_not_equal is not None:
            matches = matches + 1
        if self.match_like is not None:
            matches = matches + 1
        if (matches != 1):
            raise RuntimeError(f"Conditional rule must be either is set, is not set, is 'value', is not 'value', or like 'regex'. Instead found: {condition}")

    def is_met(self, identified: Content) -> bool:
        var_edits = identified.var_edits

        if self.match_set is not None:
            var_name = self.match_set.group(1)
            return var_name in var_edits

        elif self.match_not_set is not None:
            var_name = self.match_not_set.group(1)
            return var_name not in var_edits

        elif self.match_equal is not None:
            var_name = self.match_equal.group(1)
            expected_value = self.match_equal.group(2)
            if var_name not in var_edits:
                return False
            if (isinstance(var_edits[var_name], float)):
                # If something is a float (number), check it as an int and a float
                # Hack for integer value parsing
                if var_edits[var_name] % 1 == 0:
                    return str(int(var_edits[var_name])).strip() == expected_value.strip()
            return str(var_edits[var_name]).strip() == expected_value.strip()

        elif self.match_not_equal is not None:
            var_name = self.match_not_equal.group(1)
            unexpected_value = self.match_not_equal.group(2)
            if var_name not in var_edits:
                return True
            if (isinstance(var_edits[var_name], float)):
                # If something is a float (number), check it as an int and a float
                # Hack for integer value parsing
                if var_edits[var_name] % 1 == 0:
                    return str(int(var_edits[var_name])).strip() != unexpected_value.strip()
            return str(var_edits[var_name]).strip() != unexpected_value.strip()

        elif self.match_like is not None:
            var_name = self.match_like.group(1)
            pattern = self.match_like.group(2)
            return (var_name in var_edits) and re.match(pattern, str(var_edits[var_name]))

        return False

    def match_string(self, parent_intersection: bool) -> str:
        return self.condition

# A conditional group (Joining with AND and OR)
class WhenGroup(ConditionalRule):
    conditions: list[ConditionalRule]
    all_group: bool

    def __init__(self, conditions: list[Union[dict, str]], all_group: bool = True):
        self.conditions = [self.parse_condition(condition) for condition in conditions]
        self.all_group = all_group

    def parse_condition(self, condition: Union[dict, str]) -> ConditionalRule:
        if isinstance(condition, dict):
            if "all" in condition:
                return WhenGroup(condition["all"], all_group=True)
            elif "any" in condition:
                return WhenGroup(condition["any"], all_group=False)
            else:
                raise RuntimeError(f"Unknown conditional group in when clause: {list(condition.keys())[0]}")
        elif isinstance(condition, str):
            return WhenCondition(condition)
        else:
            raise RuntimeError(f"Invalid condition type: {type(condition)}")

    def is_met(self, identified: Content) -> bool:
        if self.all_group:
            # For `all` group, all conditions must be met
            return all(condition.is_met(identified) for condition in self.conditions)
        else:
            # For `any` group, only one condition must be met
            return any(condition.is_met(identified) for condition in self.conditions)

    # Add parenthesis where required
    def match_string(self, parent_intersection: bool) -> str:
        match_symbol = " and " if self.all_group else " or "
        match_text = match_symbol.join(condition.match_string(self.all_group) for condition in self.conditions);
        if (self.all_group == False and parent_intersection == True and len(self.conditions) > 1):
            return f"({match_text})"
        else:
            return match_text

class When:
    root_group: WhenGroup

    def __init__(self, conditions: list[Union[dict, str]]):
        expect(isinstance(conditions, list), "when must be a list of conditions.")
        # Default to 'all' group if there are multiple conditions with no explicit 'any' or 'all'
        if len(conditions) > 1 and not any(isinstance(cond, dict) for cond in conditions):
            self.root_group = WhenGroup(conditions, all_group=True)
        else:
            self.root_group = WhenGroup(conditions)

    def evaluate(self, identified: Content) -> bool:
        return self.root_group.is_met(identified)

    def match_string(self) -> str:
        return f" when {self.root_group.match_string(True)}";

class RequiredAdjacent:
    side: str
    neighbors: list[AtomNeighbor]
    skip: list[TypepathExtra]

    def __init__(self, data):
        expect(isinstance(data, dict), "required_adjacent must be a dictionary.")
        self.side = data.pop("side", "reverse")
        expect(self.side in ("reverse", "dir", "north", "south", "east", "west"), "required_adjacent side must be reverse, dir, north, south, east, or west.")
        expect("neighbors" in data, "required_adjacent must specify neighbors.")
        self.neighbors = parse_neighbor_list(data.pop("neighbors"))
        self.skip = []
        if "skip" in data:
            skip_data = data.pop("skip")
            expect(isinstance(skip_data, list), "required_adjacent skip must be a list of typepaths.")
            self.skip = [TypepathExtra(tp) for tp in skip_data]
        expect(len(data) == 0, f"Unknown key in required_adjacent: {', '.join(data.keys())}.")

    def neighbor_dir(self, atom_dir: int) -> int:
        if self.side == "reverse":
            return BYOND_REVERSE_DIR.get(atom_dir, 1)
        if self.side == "dir":
            return atom_dir if atom_dir in BYOND_DIR_OFFSETS else DEFAULT_ATOM_DIR
        return {"north": 1, "south": 2, "east": 4, "west": 8}[self.side]

    def neighbor_offset(self, atom_dir: int) -> tuple[int, int]:
        return BYOND_DIR_OFFSETS[self.neighbor_dir(atom_dir)]


class Rules:
    banned: bool = False
    banned_neighbors: list[AtomNeighbor] = []
    banned_variables: bool | list[BannedVariable] = []
    required_neighbors: list[AtomNeighbor] = []
    required_on_map: list[TypepathExtra] = []
    required_adjacent: Optional[RequiredAdjacent] = None
    ignored_neighbors: list[AtomNeighbor] = []
    when: Optional[When] = None
    skip_files: list[Union[str, re.Pattern]] = []

    def __init__(self, data):
        expect(isinstance(data, dict), "Lint rules must be a dictionary.")

        if "ignore" in data:
            ignored_neighbors_data = data.pop("ignore")
            expect(isinstance(ignored_neighbors_data, list), "'ignore' must be a list of typepaths.")
            self.ignored_neighbors = [TypepathExtra(tp) for tp in ignored_neighbors_data]

        if "banned" in data:
            self.banned = data.pop("banned")
        expect(isinstance(self.banned, bool), "banned must be a boolean.")

        if "banned_neighbors" in data:
            banned_neighbors_data = data.pop("banned_neighbors")

            expect(isinstance(banned_neighbors_data, list) or isinstance(banned_neighbors_data, dict), "banned_neighbors must be a list, or a dictionary keyed by type.")

            if isinstance(banned_neighbors_data, dict):
                self.banned_neighbors = [AtomNeighbor(typepath, data) for typepath, data in banned_neighbors_data.items()]
            else:
                self.banned_neighbors = [AtomNeighbor(typepath) for typepath in banned_neighbors_data]

        if "required_neighbors" in data:
            self.required_neighbors = parse_neighbor_list(data.pop("required_neighbors"))

        if "required_on_map" in data:
            required_on_map_data = data.pop("required_on_map")
            expect(isinstance(required_on_map_data, list), "required_on_map must be a list of typepaths.")
            self.required_on_map = [TypepathExtra(tp) for tp in required_on_map_data]

        if "required_adjacent" in data:
            self.required_adjacent = RequiredAdjacent(data.pop("required_adjacent"))

        if "banned_variables" in data:
            banned_variables_data = data.pop("banned_variables")
            if banned_variables_data == True:
                self.banned_variables = True
            else:
                expect(isinstance(banned_variables_data, list) or isinstance(banned_variables_data, dict), "banned_variables must be a list, or a dictionary keyed by variable.")

                if isinstance(banned_variables_data, dict):
                    self.banned_variables = [BannedVariable(variable, data) for variable, data in banned_variables_data.items()]
                else:
                    self.banned_variables = [BannedVariable(variable) for variable in banned_variables_data]

        if "when" in data:
            self.when = When(data.pop("when"))

        if "skip_files" in data:
            skip_files_data = data.pop("skip_files")
            expect(isinstance(skip_files_data, list), "skip_files must be a list.")
            self.skip_files = []
            for entry in skip_files_data:
                if isinstance(entry, str):
                    self.skip_files.append(entry)
                elif isinstance(entry, dict) and "pattern" in entry:
                    pattern = entry.pop("pattern")
                    self.skip_files.append(re.compile(pattern))
                    expect(len(entry) == 0, f"Unknown key in skip_files entry: {', '.join(entry.keys())}.")
                else:
                    raise MapParseError("skip_files entries must be strings or dicts with a 'pattern' key.")

        expect(len(data) == 0, f"Unknown lint rules: {', '.join(data.keys())}.")

    def skips_file(self, filename) -> bool:
        if not self.skip_files or filename is None:
            return False
        norm = str(filename).replace("\\", "/")
        for entry in self.skip_files:
            if isinstance(entry, str):
                if entry in norm:
                    return True
            elif entry.search(norm):
                return True
        return False

    def run(self, identified: Content, contents: list[Content], identified_index) -> list[MaplintError]:
        failures: list[MaplintError] = []
        when_text = self.when.match_string() if self.when is not None else ""

        if self.skips_file(getattr(identified, "filename", None)):
            return failures

        # If a when is present and is unmet, skip evaluation of this rule
        if self.when and not self.when.evaluate(identified):
            return failures

        if self.banned:
            failures.append(fail_content(identified, f"Typepath {identified.path} is banned{when_text}."))

        for banned_neighbor in self.banned_neighbors:
            ignored = False
            for neighbor in contents[:identified_index] + contents[identified_index + 1:]:
                if any(ignore.matches_path(neighbor.path) for ignore in self.ignored_neighbors):
                    ignored = True
                    break
            if ignored:
                continue

            for neighbor in contents[:identified_index] + contents[identified_index + 1:]:
                if not banned_neighbor.matches(identified, neighbor):
                    continue

                failures.append(fail_content(identified, f"Typepath {identified.path} has a banned path on the same tile{when_text}: {neighbor.path}"))

        for required_neighbor in self.required_neighbors:
            found = False
            for neighbor in contents[:identified_index] + contents[identified_index + 1:]:
                if required_neighbor.matches(identified, neighbor):
                    found = True
                    break
            if found == False:
                failures.append(fail_content(identified, f"Typepath {identified.path} is missing a required neighbor{when_text}: {required_neighbor.to_string()}"))

        if self.banned_variables == True:
            if len(identified.var_edits) > 0:
                failures.append(fail_content(identified, f"Typepath {identified.path} should not have any variable edits{when_text}."))
        else:
            assert isinstance(self.banned_variables, list)
            for banned_variable in self.banned_variables:
                if banned_variable.variable in identified.var_edits:
                    ban_reason = banned_variable.run(identified)
                    if ban_reason is None:
                        continue
                    failures.append(fail_content(identified, f"Typepath {identified.path} has a banned variable (set to {identified.var_edits[banned_variable.variable]}){when_text}: {banned_variable.variable}. {ban_reason}"))

        return failures

class Lint:
    help: Optional[str] = None
    rules: dict[TypepathExtra, Rules]
    disabled: bool = False

    def __init__(self, data):
        expect(isinstance(data, dict), "Lint must be a dictionary.")

        if "help" in data:
            self.help = data.pop("help")

        expect(isinstance(self.help, str) or self.help is None, "Lint help must be a string.")

        self.rules = {}

        for typepath, rules in data.items():
            self.rules[TypepathExtra(typepath)] = Rules(rules)

    def run(self, map_data: DMM) -> list[MaplintError]:
        all_failures: list[MaplintError] = []
        (width, height) = map_data.size()

        for pop, contents in map_data.pops.items():
            for typepath_extra, rules in self.rules.items():
                for content_index, content in enumerate(contents):
                    if not typepath_extra.matches_path(content.path):
                        continue

                    failures = rules.run(content, contents, content_index)
                    if len(failures) == 0:
                        continue

                    coordinates = map_data.turfs_for_pop(pop)
                    coordinate_texts = []

                    for _ in range(3):
                        coordinate = next(coordinates, None)
                        if coordinate is None:
                            break

                        x = coordinate[0] + 1
                        y = height - coordinate[1]
                        z = coordinate[2] + 1

                        coordinate_texts.append(f"({x}, {y}, {z})")

                    leftover_coordinates = sum(1 for _ in coordinates)
                    if leftover_coordinates > 0:
                        coordinate_texts.append(f"and {leftover_coordinates} more")

                    for failure in failures:
                        failure.coordinates = ', '.join(coordinate_texts)
                        failure.help = self.help
                        failure.pop_id = pop
                        all_failures.append(failure)

        all_failures.extend(self.run_map_rules(map_data, width, height))
        return list(set(all_failures))

    def run_map_rules(self, map_data: DMM, width: int, height: int) -> list[MaplintError]:
        failures: list[MaplintError] = []
        present_identities: list[tuple[TypepathExtra, Rules, Content]] = []

        for typepath_extra, rules in self.rules.items():
            if not rules.required_on_map and rules.required_adjacent is None:
                continue
            for contents in map_data.pops.values():
                for content in contents:
                    if not typepath_extra.matches_path(content.path):
                        continue
                    if rules.skips_file(getattr(content, "filename", None)):
                        continue
                    if rules.when and not rules.when.evaluate(content):
                        continue
                    present_identities.append((typepath_extra, rules, content))

        checked_on_map: set[int] = set()
        for _, rules, content in present_identities:
            if not rules.required_on_map or id(rules) in checked_on_map:
                continue
            checked_on_map.add(id(rules))
            when_text = rules.when.match_string() if rules.when is not None else ""
            for required in rules.required_on_map:
                if map_has_type(map_data, required):
                    continue
                failure = fail_content(content, f"Map with {content.path} is missing a required type{when_text}: {required.typepath.path}")
                failure.help = self.help
                failures.append(failure)

        if any(rules.required_adjacent for _, rules, _ in present_identities):
            failures.extend(self.run_adjacent_rules(map_data, width, height))

        return failures

    def run_adjacent_rules(self, map_data: DMM, width: int, height: int) -> list[MaplintError]:
        failures: list[MaplintError] = []
        for z, z_level in enumerate(map_data.turfs):
            for x, column in enumerate(z_level):
                for y, pop in enumerate(column):
                    contents = map_data.pops[pop]
                    for content in contents:
                        for typepath_extra, rules in self.rules.items():
                            adjacent = rules.required_adjacent
                            if adjacent is None or not typepath_extra.matches_path(content.path):
                                continue
                            if rules.skips_file(getattr(content, "filename", None)):
                                continue
                            if rules.when and not rules.when.evaluate(content):
                                continue
                            if any(skip.matches_path(content.path) for skip in adjacent.skip):
                                continue
                            atom_dir = parse_atom_dir(content)
                            dx, dy = adjacent.neighbor_offset(atom_dir)
                            nx, ny = x + dx, y + dy
                            when_text = rules.when.match_string() if rules.when is not None else ""
                            side_name = BYOND_DIR_NAMES.get(adjacent.neighbor_dir(atom_dir), "adjacent")
                            neighbor_contents = contents_at(map_data, nx, ny, z)
                            for required in adjacent.neighbors:
                                if any(required.matches(content, neighbor) for neighbor in neighbor_contents):
                                    continue
                                failure = fail_content(content, f"Typepath {content.path} is missing {required.to_string()} on the {side_name} tile{when_text}.")
                                failure.coordinates = f"({x + 1}, {height - y}, {z + 1})"
                                failure.help = self.help
                                failure.pop_id = pop
                                failures.append(failure)
        return failures


def map_has_type(map_data: DMM, typepath_extra: TypepathExtra) -> bool:
    for contents in map_data.pops.values():
        for content in contents:
            if typepath_extra.matches_path(content.path):
                return True
    return False


def contents_at(map_data: DMM, x: int, y: int, z: int) -> list[Content]:
    if z < 0 or z >= len(map_data.turfs):
        return []
    z_level = map_data.turfs[z]
    if x < 0 or x >= len(z_level):
        return []
    column = z_level[x]
    if y < 0 or y >= len(column):
        return []
    return map_data.pops[column[y]]
