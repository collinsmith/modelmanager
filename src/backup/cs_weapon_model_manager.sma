#define VERSION_STRING "0.0.1"
#define DEBUG_MODE

#include <amxmodx>

#include "include/templates/weaponmodel_t.inc"
#include "include/cs_model_manager.inc"
#include "include/cs_precache_stocks.inc"
#include "include/param_test_stocks.inc"

#define INITIAL_MODELS_SIZE 8

#define copyAndTerminate(%1,%2,%3,%4)\
    %4 = get_string(%1, %2, %3);\
    %2[%4] = EOS

#define copyInto(%1,%2)\
    new Model:parentModel = cs_getModelData(\
            getInternalWeaponModelParentHandle(%1),\
            g_tempModel);\
        assert cs_isValidModel(parentModel);\
        getWeaponModelParent(%2) = g_tempModel;\
        getWeaponModelWeapon(%2) = getInternalWeaponModelWeapon(%1)

#define isEmpty(%1)\
    (%1[0] == EOS)

enum internal_weaponmodel_t {
    Model:internal_weaponmodel_ParentHandle,
    internal_weaponmodel_Weapon
}

#define getInternalWeaponModelParentHandle(%1)\
    %1[internal_weaponmodel_ParentHandle]

#define getInternalWeaponModelWeapon(%1)\
    %1[internal_weaponmodel_Weapon]

enum _:Forward {
    returnVal = 0,
    onWeaponModelRegistered,
    onSetUserWeaponModelPre,
    onSetUserWeaponModelPost
};

static g_fw[Forward] = { INVALID_HANDLE, ... };

static Array:g_modelList = Invalid_Array;
static Trie:g_modelTrie = Invalid_Trie;
static g_numModels = 0;

static g_weapon[2];
static Trie:g_currentModel[MAX_PLAYERS+1] = { Invalid_Trie, ... };
static WeaponModel:g_newModel;
static bool:g_isInOnSetUserWeaponModelPre;
static g_tempModel[model_t];
static g_tempWeaponModel[weaponmodel_t];
static g_tempInternalWeaponModel[internal_weaponmodel_t];

public plugin_natives() {
    register_library("cs_weapon_model_manager");

    register_native("cs_registerWeaponModel", "_registerWeaponModel", 0);
    register_native("cs_findWeaponModelByName", "_findWeaponModelByName", 0);
    register_native("cs_getWeaponModelData", "_getWeaponModelData", 0);
    register_native("cs_getWeaponForModel", "_getWeaponForModel", 0);
    register_native("cs_isValidWeaponModel", "_isValidWeaponModel", 0);
    register_native("cs_validateWeaponModel", "_validateWeaponModel", 0);

    register_native("cs_setUserWeaponModel", "_setUserWeaponModel", 0);
    register_native("cs_getUserWeaponModel", "_getUserWeaponModel", 0);
    register_native("cs_resetUserWeaponModel", "_resetUserWeaponModel", 0);
    register_native("cs_changeOnSetUserWeaponModelModel", "_changeOnSetUserWeaponModelModel", 0);
}

public plugin_init() {
    register_plugin("CS Weapon Model Manager", VERSION_STRING, "Tirant");

#if defined DEBUG_MODE
    register_concmd(
            "models.weapons.list",
            "printModels",
            ADMIN_CFG,
            "Prints the list of registered weapon models");

    register_concmd(
            "models.weapons.get",
            "printCurrentModels",
            ADMIN_CFG,
            "Prints each player and the current weapon models they have applied");
#endif
}

/*******************************************************************************
 * Console Commands
 ******************************************************************************/

#if defined DEBUG_MODE
public printModels(id) {
    console_print(id, "Outputting weapon models list...");
    for (new i = 0; i < g_numModels; i++) {
        ArrayGetArray(g_modelList, i, g_tempInternalWeaponModel);
        cs_getModelData(
                getInternalWeaponModelParentHandle(g_tempInternalWeaponModel),
                g_tempModel);
        console_print(
                id,
                "%d. %s [%s]",
                i+1,
                getModelName(g_tempModel),
                getModelPath(g_tempModel));
    }
    
    console_print(id, "%d weapon models registered", g_numModels);
}

public printCurrentModels(id) {
    console_print(id, "Outputting players...");
    new const szWEAPON_NAME[][] = {
        "",
        "weapon_p228",
        "",
        "weapon_scout",
        "weapon_hegrenade",
        "weapon_xm1014",
        "weapon_c4",
        "weapon_mac10",
        "weapon_aug",
        "weapon_smokegrenade",
        "weapon_elite",
        "weapon_fiveseven",
        "weapon_ump45",
        "weapon_sg550",
        "weapon_galil",
        "weapon_famas",
        "weapon_usp",
        "weapon_glock18",
        "weapon_awp",
        "weapon_mp5navy",
        "weapon_m249",
        "weapon_m3",
        "weapon_m4a1",
        "weapon_tmp",
        "weapon_g3sg1",
        "weapon_flashbang",
        "weapon_deagle",
        "weapon_sg552",
        "weapon_ak47",
        "weapon_knife",
        "weapon_p90",
        "weapon_vest",
        "weapon_vesthelm",
        "csi_defuser",
        "csi_nvgs",
        "",
        "csi_priammo",
        "csi_secammo",
        "csi_shield"
    };

    new Snapshot:entries, numEntries, WeaponModel:model;
    for (new i = 1; i <= MaxClients; i++) {
        if (!is_user_connected(i)) {
            console_print(id, "%d. DISCONNECTED", i);
            continue;
        }

        console_print(id, "%d. %N", i, i);
        if (g_currentModel[i] == Invalid_Trie) {
            continue;
        }
        
        entries = TrieSnapshotCreate(g_currentModel[i]);
        numEntries = TrieSnapshotLength(entries);
        for (new j = 0; j < numEntries; j++) {
            TrieSnapshotGetKey(entries, j, g_weapon, 1);
            TrieGetCell(g_currentModel[i], g_weapon, model);
            ArrayGetArray(g_modelList, any:model-1, g_tempInternalWeaponModel);
            cs_getModelData(
                    getInternalWeaponModelParentHandle(g_tempInternalWeaponModel),
                    g_tempModel);
            console_print(
                    id,
                    "\t%s = %s",
                    szWEAPON_NAME[g_weapon[0]],
                    getModelName(g_tempModel));
        }

        TrieSnapshotDestroy(entries);
    }
    
    console_print(id, "Done.");
}
#endif

stock const _validWeapon1 = 0xFFFFFFFD;
stock const _validWeapon2 = 0x2D;

stock bool:isValidWeapon(weapon) {
    switch (weapon) {
        case  1..32: return ((1<<(weapon- 1))&_validWeapon1) != 0;
        case 33..38: return ((1<<(weapon-33))&_validWeapon2) != 0;
        default:     return false;
    }

    return false;
}

bool:isValidWeaponModel(WeaponModel:model) {
    return Invalid_Weapon_Model < model && any:model <= g_numModels;
}

bool:validateParent(WeaponModel:model) {
    assert isValidWeaponModel(model);
    ArrayGetArray(g_modelList, any:model-1, g_tempInternalWeaponModel);
    return cs_isValidModel(
            getInternalWeaponModelParentHandle(g_tempInternalWeaponModel));
}

WeaponModel:findWeaponModelByName(name[]) {
    strtolower(name);
    new WeaponModel:model;
    if (TrieGetCell(g_modelTrie, name, model)) {
        return model;
    }

    return Invalid_Weapon_Model;
}

getWeaponForModel(WeaponModel:model) {
    assert isValidWeaponModel(model);
    ArrayGetArray(g_modelList, any:model-1, g_tempInternalWeaponModel);
    return getInternalWeaponModelWeapon(g_tempInternalWeaponModel);
}

bool:isInvalidWeaponModelHandleParam(const function[], WeaponModel:model) {
    if (!isValidWeaponModel(model)) {
        log_error(
                AMX_ERR_NATIVE,
                "[%s] Invalid weapon model handle specified: %d",
                function,
                model);
        return true;
    }

    return false;
}

stock bool:isInvalidModelHandleParam(const function[], WeaponModel:model) {
    if (!validateParent(model)) {
        log_error(
                AMX_ERR_NATIVE,
                "[%s] Invalid model handle for parent of weapon model: %d",
                function,
                getInternalWeaponModelParentHandle(g_tempInternalWeaponModel));
        return true;
    }

    return false;
}

bool:isInvalidWeaponParam(const function[], weapon) {
    if (!isValidWeapon(weapon)) {
        log_error(
                AMX_ERR_NATIVE,
                "[%s] Invalid weapon specified: $d",
                function,
                weapon);
        return true;
    }

    return false;
}

/*******************************************************************************
 * NATIVES
 ******************************************************************************/

/**
 * @link #cs_registerWeaponModel(weapon, name[])
 */
public WeaponModel:_registerWeaponModel(pluginId, numParams) {
#if defined DEBUG_MODE
    if (isInvalidNumberOfParams("cs_registerWeaponModel", numParams, 2)) {
        return Invalid_Weapon_Model;
    }
#endif

    if (g_modelList == Invalid_Array) {
        g_modelList = ArrayCreate(internal_weaponmodel_t, INITIAL_MODELS_SIZE);
    }

    if (g_modelTrie == Invalid_Trie) {
        g_modelTrie = TrieCreate();
    }

    new weapon = g_tempWeaponModel[weaponmodel_Weapon]
            = getInternalWeaponModelWeapon(g_tempInternalWeaponModel)
            = get_param(1);

    if (isInvalidWeaponParam("cs_registerWeaponModel", weapon)) {
        return Invalid_Weapon_Model;
    }

    copyAndTerminate(2,getModelName(getWeaponModelParent(g_tempWeaponModel)),model_Name_length,getModelNameLength(getWeaponModelParent(g_tempWeaponModel)));
    
    new WeaponModel:model = findWeaponModelByName(getModelName(getWeaponModelParent(g_tempWeaponModel)));
    if (isValidWeaponModel(model)) {
        return model;
    }

    getModelPathLength(getWeaponModelParent(g_tempWeaponModel)) = cs_formatModelPath(
            getModelName(getWeaponModelParent(g_tempWeaponModel)),
            getModelPath(getWeaponModelParent(g_tempWeaponModel)),
            model_Path_length);

    new Model:parent = getInternalWeaponModelParentHandle(g_tempInternalWeaponModel)
             = cs_registerModel(
                getModelName(getWeaponModelParent(g_tempWeaponModel)),
                getModelPath(getWeaponModelParent(g_tempWeaponModel)));
    if (!cs_isValidModel(parent)) {
        // Error already reported while registering
        return Invalid_Weapon_Model;
    }

    model = WeaponModel:(ArrayPushArray(g_modelList, g_tempInternalWeaponModel)+1);
    TrieSetCell(g_modelTrie, getModelName(getWeaponModelParent(g_tempWeaponModel)), model);
    g_numModels++;

    if (g_fw[onWeaponModelRegistered] == INVALID_HANDLE) {
        g_fw[onWeaponModelRegistered] = CreateMultiForward(
                "cs_onWeaponModelRegistered",
                ET_IGNORE,
                FP_CELL,
                FP_ARRAY);
    }

    g_fw[returnVal] = ExecuteForward(
            g_fw[onWeaponModelRegistered],
            g_fw[returnVal],
            model,
            PrepareArray(g_tempWeaponModel, weaponmodel_t));

    if (g_fw[returnVal] == 0) {
        log_error(
                AMX_ERR_NATIVE,
                "[cs_registerWeaponModel] Failed to execute \
                    cs_onWeaponModelRegistered for model: %s [%s]",
                getModelName(getWeaponModelParent(g_tempWeaponModel)),
                getModelPath(getWeaponModelParent(g_tempWeaponModel)));
    }

    return model;
}

/**
 * @link #cs_findWeaponModelByName(name[],...)
 */
public WeaponModel:_findWeaponModelByName(pluginId, numParams) {
#if defined DEBUG_MODE
    if (isInvalidNumberOfParamsInRange("cs_findWeaponModelByName", numParams, 1, 2)) {
        return Invalid_Weapon_Model;
    }
#endif

    if (g_modelList == Invalid_Array || g_modelTrie == Invalid_Trie) {
        return Invalid_Weapon_Model;
    }

    copyAndTerminate(1,getModelName(getWeaponModelParent(g_tempWeaponModel)),model_Name_length,getModelNameLength(getWeaponModelParent(g_tempWeaponModel)));
    if (isEmpty(getModelName(getWeaponModelParent(g_tempWeaponModel)))) {
        return Invalid_Weapon_Model;
    }

    new WeaponModel:model = findWeaponModelByName(getModelName(getWeaponModelParent(g_tempWeaponModel)));
    if (isValidWeaponModel(model) && numParams == 2) {
        ArrayGetArray(g_modelList, any:model-1, g_tempInternalWeaponModel);
        copyInto(g_tempInternalWeaponModel,g_tempWeaponModel);
        set_array(2, g_tempWeaponModel, weaponmodel_t);
    }

    return model;
}

/**
 * @link #cs_getWeaponModelData(model,data[weaponmodel_t])
 */
public WeaponModel:_getWeaponModelData(pluginId, numParams) {
#if defined DEBUG_MODE
    if (isInvalidNumberOfParams("cs_getWeaponModelData", numParams, 2)) {
        return Invalid_Weapon_Model;
    }

    // TODO: Perform validation on the outgoing array size
    //if () {
    //    return Invalid_Weapon_Model;
    //}
#endif

    new WeaponModel:model = WeaponModel:get_param(1);
    if (isInvalidWeaponModelHandleParam("cs_getWeaponModelData", model)) {
        return Invalid_Weapon_Model;
    }

    ArrayGetArray(g_modelList, any:model-1, g_tempInternalWeaponModel);
    copyInto(g_tempInternalWeaponModel,g_tempWeaponModel);
    set_array(2, g_tempWeaponModel, weaponmodel_t);
    return model;
}

/**
 * @link #cs_getWeaponForModel(model)
 */
public _getWeaponForModel(pluginId, numParams) {
#if defined DEBUG_MODE
    if (isInvalidNumberOfParams("cs_getWeaponForModel", numParams, 1)) {
        return -1;
    }
#endif

    new WeaponModel:model = WeaponModel:get_param(1);
    if (!isValidWeaponModel(model)) {
        return -1;
    }

    return getWeaponForModel(model);
}

/**
 * @link #cs_isValidWeaponModel(model)
 */
public bool:_isValidWeaponModel(pluginId, numParams) {
#if defined DEBUG_MODE
    if (isInvalidNumberOfParams("cs_isValidWeaponModel", numParams, 1)) {
        return false;
    }
#endif

    new WeaponModel:model = WeaponModel:get_param(1);
    return isValidWeaponModel(model);
}

/**
 * @link #_validateWeaponModel(model)
 */
public bool:_validateWeaponModel(pluginId, numParams) {
#if defined DEBUG_MODE
    if (isInvalidNumberOfParams("cs_validateWeaponModel", numParams, 1)) {
        return false;
    }
#endif

    new WeaponModel:model = WeaponModel:get_param(1);
    return isValidWeaponModel(model) && validateParent(model);
}

/**
 * @link #cs_setUserWeaponModel(id,model)
 */
public _setUserWeaponModel(pluginId, numParams) {
#if defined DEBUG_MODE
    if (isInvalidNumberOfParams("cs_setUserWeaponModel", numParams, 2)) {
        return;
    }
#endif

    new id = get_param(1);
    if (isInvalidPlayerIndexParam("cs_setUserWeaponModel", id)) {
        return;
    }

    if (isInvalidPlayerConnectedParam("cs_setUserWeaponModel", id)) {
        return;
    }

    g_newModel = WeaponModel:get_param(2);
    if (isInvalidWeaponModelHandleParam("cs_setUserWeaponModel", g_newModel)) {
        return;
    }

#if defined DEBUG_MODE
    if (isInvalidModelHandleParam("cs_setUserWeaponModel", g_newModel)) {
        return;
    }
#endif

    if (g_fw[onSetUserWeaponModelPre] == INVALID_HANDLE) {
        g_fw[onSetUserWeaponModelPre] = CreateMultiForward(
                "cs_onSetUserWeaponModelPre",
                ET_STOP,
                FP_CELL,
                FP_CELL,
                FP_CELL);
    }

    g_weapon[0] = getWeaponForModel(g_newModel);
    if (g_currentModel[id] == Invalid_Trie) {
        g_currentModel[id] = TrieCreate();
        TrieSetCell(g_currentModel[id], g_weapon, Invalid_Weapon_Model);
    }

    new WeaponModel:oldModel;
    TrieGetCell(g_currentModel[id], g_weapon, oldModel);
    g_isInOnSetUserWeaponModelPre = true;
    g_fw[returnVal] = ExecuteForward(
            g_fw[onSetUserWeaponModelPre],
            g_fw[returnVal],
            oldModel,
            g_newModel);
    g_isInOnSetUserWeaponModelPre = false;

    if (g_fw[returnVal] == 0) {
        log_error(
                AMX_ERR_NATIVE,
                "[cs_setUserWeaponModel] Failed to execute \
                    cs_onSetUserWeaponModelPre on player %N",
                id);
    }

    copyInto(g_tempInternalWeaponModel,g_tempWeaponModel);
    //cs_set_user_model(id, getModelName(getWeaponModelParent(g_tempWeaponModel)));
    TrieSetCell(g_currentModel[id], g_weapon, g_newModel);

    if (g_fw[onSetUserWeaponModelPost] == INVALID_HANDLE) {
        g_fw[onSetUserWeaponModelPost] = CreateMultiForward(
                "cs_onSetUserWeaponModelPost",
                ET_IGNORE,
                FP_CELL,
                FP_CELL,
                FP_CELL);
    }

    g_fw[returnVal] = ExecuteForward(
            g_fw[onSetUserWeaponModelPost],
            g_fw[returnVal],
            oldModel,
            g_newModel);

    if (g_fw[returnVal] == 0) {
        log_error(
                AMX_ERR_NATIVE,
                "[cs_setUserWeaponModel] Failed to execute \
                    cs_onSetUserWeaponModelPost on player %N",
                id);
    }
}

/**
 * @link #cs_getUserWeaponModel(id,weapon)
 */
public WeaponModel:_getUserWeaponModel(pluginId, numParams) {
#if defined DEBUG_MODE
    if (isInvalidNumberOfParams("cs_getUserWeaponModel", numParams, 2)) {
        return Invalid_Weapon_Model;
    }
#endif

    new id = get_param(1);
    if (isInvalidPlayerIndexParam("cs_getUserWeaponModel", id)) {
        return Invalid_Weapon_Model;
    }

    if (isInvalidPlayerConnectedParam("cs_getUserWeaponModel", id)) {
        return Invalid_Weapon_Model;
    }

    g_weapon[0] = get_param(2);
    if (isInvalidWeaponParam("cs_getUserWeaponModel", g_weapon[0])) {
        return Invalid_Weapon_Model;
    }

    if (g_currentModel[id] == Invalid_Trie) {
        return Invalid_Weapon_Model;
    }

    new WeaponModel:weapon;
    TrieGetCell(g_currentModel[id], g_weapon, weapon);
    return weapon;
}

/**
 * @link #cs_resetUserWeaponModel(id,weapon)
 */
public _resetUserWeaponModel(pluginId, numParams) {
#if defined DEBUG_MODE
    if (isInvalidNumberOfParams("cs_resetUserWeaponModel", numParams, 2)) {
        return;
    }
#endif
    
    new id = get_param(1);
    if (isInvalidPlayerIndexParam("cs_resetUserWeaponModel", id)) {
        return;
    }

    if (isInvalidPlayerConnectedParam("cs_resetUserWeaponModel", id)) {
        return;
    }

    g_weapon[0] = get_param(2);
    if (isInvalidWeaponParam("cs_resetUserWeaponModel", g_weapon[0])) {
        return;
    }
    
    //cs_reset_user_model(id, weapon);
    
    if (g_currentModel[id] != Invalid_Trie) {
        TrieSetCell(g_currentModel[id], g_weapon, Invalid_Weapon_Model);
    }
}

/**
 * @link #cs_changeOnSetUserWeaponModelModel(model)
 */
public _changeOnSetUserWeaponModelModel(pluginId, numParams) {
    if (!g_isInOnSetUserWeaponModelPre) {
        log_error(
                AMX_ERR_NATIVE,
                "[cs_changeOnSetUserWeaponModelModel] Invalid state. Can only \
                    call this during cs_onSetUserWeaponModelPre");
        return;
    }

#if defined DEBUG_MODE
    if (isInvalidNumberOfParams("cs_changeOnSetUserWeaponModelModel", numParams, 1)) {
        return;
    }
#endif

    new WeaponModel:newModel = WeaponModel:get_param(1);
    if (isInvalidWeaponModelHandleParam("cs_changeOnSetUserWeaponModelModel", newModel)) {
        return;
    }

#if defined DEBUG_MODE
    if (isInvalidModelHandleParam("cs_changeOnSetUserWeaponModelModel", newModel)) {
        return;
    }
#endif

    g_newModel = newModel;
}